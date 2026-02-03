# Data Loading

Downloading and importing navigation and terrain data.

## Overview

SF50 TOLD requires two categories of data to calculate performance:

1. **Navigation Data**: Airport and runway information from FAA NASR and OurAirports
2. **Terrain Data**: SRTM elevation data for departure climb analysis

Navigation data is required and loaded on first launch. Terrain data is optional
and downloaded on-demand by region.

## Navigation Data

Navigation data is pre-processed from FAA NASR and OurAirports sources, compressed,
and hosted on GitHub. The ``NavDataLoader`` actor downloads and imports this data
into SwiftData on first launch and when updates are available.

### Data Pipeline

![Airport Loading Pipeline](airport-loading-pipeline)

### Update Decision Logic

``NavDataLoaderViewModel`` determines when to show the loading UI based on:

### Required Load (Cannot Skip)

- No airports in database (`noData`)
- Schema version mismatch (app update changed data format)

### Optional Load (Can Defer)

- AIRAC cycle expired but data exists
- User can tap "Load Later" to defer

### Current Data

- Schema matches and cycle is effective
- No loader UI shown

```swift
var showLoader: Bool {
    (noData || needsLoad) && !deferred
}
```

## AIRAC Cycles

Airport data is organized by AIRAC (Aeronautical Information Regulation And
Control) cycles—28-day periods used in aviation. The app checks if the loaded
cycle is still effective:

```swift
private func outOfDate(cycle: Cycle?) -> Bool {
    if let cycle, cycle.isEffective { return false }
    return true
}
```

New cycle data is typically uploaded to GitHub a few days before the cycle
becomes effective. If data isn't available yet, ``NavDataLoader`` throws
``NavDataLoader/Errors/cycleNotAvailable``.

## Loading Progress

The loader reports progress through the ``NavDataLoader/State`` enum:

| State | Description |
|-------|-------------|
| `.downloading(progress:)` | Downloading from GitHub (0.0-1.0) |
| `.extracting(progress:)` | Decompressing LZMA |
| `.loading(progress:)` | Importing airports and obstacles (0.0-1.0) |
| `.finished` | Complete |

The `.loading` phase combines both airport and obstacle imports into a single
unified progress value, calculated from the total item count across both phases.

The view model polls the loader state every 250ms to update the UI:

```swift
Task { [weak self] in
    while !Task.isCancelled {
        let state = await loader.state
        self?.state = state
        try? await Task.sleep(for: .seconds(0.25))
    }
}
```

## Batch Import

To avoid blocking the main actor, data import uses batch processing:

1. Airports are processed in batches of 100
2. Obstacles are processed in batches of 1000
3. SwiftData is saved after each batch
4. Sub-functions report raw item counts via closures
5. The orchestrator (`load()`) calculates unified progress

```swift
let totalItems = nasr.airports.count + nasr.obstacles.count

try loadAirports(nasr.airports) { airportsProcessed in
    self.state = .loading(progress: Float(airportsProcessed) / Float(totalItems))
}

let airportCount = nasr.airports.count
try loadObstacles(nasr.obstacles) { obstaclesProcessed in
    self.state = .loading(progress: Float(airportCount + obstaclesProcessed) / Float(totalItems))
}
```

## Data Sources

The compressed data combines two sources:

### FAA NASR

National Airspace System Resources provides authoritative data for US airports:
- Precise runway lengths and distances
- Displaced thresholds
- Gradient information
- Official identifiers

### OurAirports

Community-maintained database supplements NASR with:
- International airports
- Time zone information
- Additional airports not in NASR

## Terrain Data

Terrain data enables departure climb analysis by providing ground elevation along
the departure path. This data is based on SRTM (Shuttle Radar Topography Mission)
elevation data at 3 arc-second (~90m) resolution.

### On-Demand Downloads

Unlike navigation data, terrain data is downloaded on-demand by geographic region.
This approach keeps the initial app download small while allowing users to download
terrain for regions they fly in.

``TerrainDataLoader`` manages terrain downloads:

```swift
let loader = TerrainDataLoader()

// Check if a region is available
if !loader.isRegionAvailable(.northAmerica) {
    // Request download
    try await loader.downloadRegion(.northAmerica)
}
```

### Download Progress

``TerrainDataLoader`` reports download state through the ``TerrainDataLoader/State`` enum:

| State | Description |
|-------|-------------|
| `.idle` | No active download |
| `.downloading(region:progress:)` | Downloading from Cloudflare R2 |
| `.decompressing(region:)` | Decompressing LZMA-compressed data |
| `.completed(region:)` | Download finished successfully |
| `.failed(region:message:)` | Download failed |

### Storage

Terrain files are stored in the app group container (`group.codes.tim.TOLD`)
to enable sharing with the Background Assets extension. Each region is stored as
a decompressed `.srtm` file after download.

### Regions

Terrain data is organized into geographic regions:

- **North America**: Continental US, Canada, and Mexico
- **Europe**: Western and Central Europe
- **Additional regions**: As needed for coverage

The ``TerrainRegion`` enum defines available regions and their geographic bounds.
Use ``TerrainDataLoader/regionStatus(for:)`` to determine which region covers a
specific coordinate.

## See Also

- ``NavDataLoader``
- ``NavDataLoaderViewModel``
- ``TerrainDataLoader``
- ``TerrainDataLoaderViewModel``
