# Navigation Data Processing Pipeline

Understanding how navigation data flows through DownloadNASR.

## Overview

DownloadNASR processes airport, runway, instrument procedure, and obstacle data
from multiple FAA sources and OurAirports into a compressed format optimized for
mobile distribution. This article explains each stage of the pipeline and the
data transformations applied.

## Pipeline Architecture

![Navigation Data Processing Pipeline](nav-data-processing-pipeline)

## Stage 1: FAA NASR Download

The FAA publishes National Airspace System Resources (NASR) data every 28 days
(AIRAC cycle). `NASRProcessor` uses the SwiftNASR library to:

1. Download the NASR archive for the current cycle
2. Parse airport and runway records
3. Filter to airports with runways ≥500 feet
4. Extract precise runway distances (TORA, TODA, LDA)

NASR data is authoritative for US airports and includes:

- Precise runway geometry (length, distances, gradient)
- Official identifiers (FAA LID, ICAO)
- Touchdown zone elevations
- True headings

## Stage 2: OurAirports Download

`OurAirportsLoader` downloads community-maintained CSV data to supplement
NASR with international airports:

```swift
let airportsURL = "https://davidmegginson.github.io/ourairports-data/airports.csv"
let runwaysURL = "https://davidmegginson.github.io/ourairports-data/runways.csv"
```

The loader filters to:

- Airport types: `small_airport`, `medium_airport`, `large_airport`
- Runways ≥500 feet
- Excludes water runways

## Stage 3: FAA CIFP Download

`CIFPProcessor` downloads and parses Coded Instrument Flight Procedures for the
same AIRAC cycle. CIFP data provides:

- **Departure procedures** (SIDs): Organized into segments per runway transition
  and common route, with fixes, altitude restrictions, and leg type geometry
  (track-to-fix, course-to-fix, holds, arcs, etc.)
- **Approach procedures**: Missed approach fixes with altitude constraints
- **DME-capable navaids**: VOR/DME, VORTAC, DME, and TACAN facilities referenced
  by procedure legs for DME distance termination

Each procedure leg is converted to a `LegTypeCodable` with the path terminator
type, magnetic course, turn direction (for holds), and arc radius (for RF/DME arcs).
DME-terminated legs also include the recommended navaid identifier and termination
distance. Legs with missing required data (e.g., a course-to-fix without a course)
are skipped with a warning.

## Stage 4: FAA d-TPP Chart Names

`DTPPLoader` downloads the FAA Digital Terminal Procedures Publication (d-TPP)
metafile for the same AIRAC cycle and extracts the official, as-charted title of
every instrument procedure. `ProcedureNameResolver` applies these so each
procedure carries its published name rather than one synthesized from CIFP
metadata:

- **Approaches** match a chart title on a key of navaid family, runway, and
  multiple indicator. When several charts share a key — a base chart alongside
  its CAT II/III or special-minimums variants — the lowest-penalty chart wins, so
  the approach keeps its primary charted name (`I28L` → “ILS RWY 28L”). The same
  key parses the runway from the CIFP identifier, which SwiftCIFP leaves unset.
- **Departures** cannot be matched from chart titles alone: a navaid-named SID
  charts as “VENTURA EIGHT” while CIFP calls it `VTU8`. NASR `STARDP` computer
  codes bridge the CIFP identifier to the official name, which is then joined to
  the chart title to recover suffixes NASR omits (“SSTIK FIVE” →
  “SSTIK FIVE (RNAV)”).

Naming is a nicety, so a failure here degrades procedure names rather than failing
the run: departures keep their NASR names and approaches fall back to names
generated from CIFP metadata. Against live FAA data, roughly 99.8% of approaches
and 99.5% of departures receive an official name.

## Stage 5: FAA DOF Download

`DOFProcessor` downloads the FAA Digital Obstacle File and extracts obstacles
(towers, buildings, terrain) with their coordinates and MSL heights. Only obstacles
near airports in the dataset are included to minimize file size.

## Stage 6: Merge and Deduplicate

NASR data takes priority over OurAirports. The merge process:

1. Add all NASR airports to the output set
2. Track NASR location IDs in a lookup set
3. For each OurAirports record:
   - Skip if `local_code` matches an existing NASR `locationID`
   - Otherwise add to output

This ensures US airports use authoritative FAA data while international
airports use OurAirports data.

## Stage 7: Data Enrichment

Each airport record is enriched with:

### Timezone Lookup

Using SwiftTimeZoneLookup, each airport gets its local timezone based on
coordinates. This enables local time display in the app.

### Magnetic Variation

Using the `Geomagnetism` model (World Magnetic Model), magnetic declination
is calculated for airports without NASR-provided variation data.

## Stage 8: Encoding and Compression

The final data structure is encoded as:

1. **Property List**: Binary plist format for efficient iOS parsing
2. **LZMA Compression**: Reduces file size significantly (~90% reduction)

The output filename follows the pattern: `{cycle}.plist.lzma` (e.g., `2501.plist.lzma`)

## Stage 9: GitHub Upload

If a GitHub token is configured, ``GitHubUploader`` pushes the compressed file
to the Airport-Data repository. The iOS app downloads from this location.

Upload path: `3.0/{cycle}.plist.lzma`

## Data Format

The compressed file contains an `AirportDataCodable` structure:

```text
AirportDataCodable
├── cycles: DataCycles
│   ├── nasr: CycleInfo? (effective/expires dates)
│   ├── cifp: CycleInfo?
│   └── dof: CycleInfo?
├── ourAirportsLastUpdated: Date?
├── airports: [AirportCodable]
│   ├── recordID, locationID, ICAO_ID?, name, city?
│   ├── dataSource: "nasr" | "ourAirports"
│   ├── latitude, longitude (degrees), elevation (meters)
│   ├── variation (degrees), timeZone?
│   ├── runways: [RunwayCodable]
│   │   ├── name, trueHeading, length, elevation? (threshold elevation)
│   │   ├── takeoffRun?, takeoffDistance?, landingDistance?
│   │   ├── gradient?, isTurf, reciprocalName?
│   │   ├── thresholdLatitude?, thresholdLongitude?
│   │   ├── width?, displacedThresholdDistance?
│   │   └── thresholdCrossingHeight?, glidepathAngle?
│   └── procedures: [ProcedureCodable]?
│       ├── type: "departure" | "approach"
│       ├── identifier, name? (official chart title), runwayName? (approaches)
│       ├── requiredClimbGradientFtPerNM? (departures)
│       └── segments: [SegmentCodable]?
│           ├── runwayNames: [String]? (nil for common route or missed approach)
│           └── legs: [LegCodable]
│               ├── identifier?, latitude?, longitude?
│               ├── altitudeRestriction?: AltitudeRestrictionCodable
│               ├── legType: LegTypeCodable
│               ├── recommendedNavaidIdentifier?, recommendedNavaidICAO?
│               └── dmeDistanceNM?, thetaDeg?
├── navaids: [NavaidCodable]?
│   ├── identifier, icaoRegion
│   ├── type (e.g., "VOR/DME", "VORTAC", "DME", "TACAN")
│   ├── latitude, longitude (degrees)
│   └── elevationFt?
└── obstacles: [ObstacleCodable]
    ├── heightFtMSL
    └── latitude, longitude
```

Each `LegTypeCodable` stores a discriminator (`type`) plus optional `course`
(degrees), `turnDirection`, and `arcRadius` (nautical miles).

## See Also

- ``NavDataProcessorViewModel``
- ``GitHubUploader``
