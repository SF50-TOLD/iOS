# Takeoff and Landing Report Generation

Understanding the TLR generation pipeline and Template Method pattern.

## Overview

The Takeoff and Landing Report (TLR) system generates comprehensive HTML reports
showing performance data for all runways at an airport under various conditions.
The system uses the Template Method design pattern to share common logic while
allowing takeoff and landing-specific customizations.

## Pipeline Architecture

TLR generation follows a two-phase pipeline:

![TLR Pipeline](tlr-pipeline)

### Phase 1: Data Generation

``BaseReportData`` and its subclasses calculate:

1. **Runway Analysis**: Maximum weight for each runway with limiting factor
2. **Scenario Performance**: Performance under each what-if scenario

The ``BaseReportData/generate()`` method returns a ``ReportOutput`` containing both.

### Phase 2: Rendering

``BaseReportTemplate`` and its subclasses render the data to HTML:

1. **Header**: Airport, date, aircraft, weather source
2. **Data Table**: Planned conditions summary
3. **Runways Table**: Max weights and limiting factors
4. **Performance Tables**: One per scenario (accordion for non-forecast)

The template also names the document and writes a plain-text digest of the
planned runway, so a ``Report`` carries everything sharing it needs. ``ReportPDF``
lays that HTML out as a paginated US Letter PDF.

## Template Method Pattern

Both data generation and rendering use the Template Method pattern, where
the base class defines the algorithm skeleton and subclasses provide
specific implementations.

### BaseReportData Template Methods

```swift
class BaseReportData<PerformanceType, ScenarioType> {
    // Algorithm skeleton
    func generate() throws -> ReportOutput<ScenarioType> {
        let runways = try generateRunwayInfo()
        let scenarios = try generateScenarios()
        return .init(runwayInfo: runways, scenarios: scenarios)
    }

    // Template methods (overridden by subclasses)
    func operation() -> Operation { fatalError() }
    func calculatePerformance(for:conditions:config:) throws -> PerformanceType { fatalError() }
    func determineMaxWeight(runway:) throws -> (Measurement<UnitMass>, LimitingFactor) { fatalError() }
    func createScenario(name:runways:) -> ScenarioType { fatalError() }
}
```

### Takeoff vs Landing Implementations

| Aspect | TakeoffReportData | LandingReportData |
|--------|-------------------|-------------------|
| Max Weight | `maxTakeoffWeight` | `maxLandingWeight` |
| Performance | Ground run, total distance, climb | Vref, landing run/distance, go-around |
| Constraints | AFM, field, obstacle | AFM, field, climb gradient |

## Max Weight Determination

Both subclasses call the SF50Performance package's limit searches,
`PerformanceCalculator.maxTakeoffWeight` and `maxLandingWeight`, which bisect
in 50 lb steps from the empty weight to the structural maximum and check:

1. The AFM's wind, airport elevation and temperature limitations
2. AFM chart limits (a figure the tables give)
3. Available runway length
4. Operation-specific constraints (obstacle clearance from the 50 ft screen,
   or the go-around climb gradient)

``BaseReportData/generateRunwayInfo()`` turns the search's binding constraint
into a ``LimitingFactor``. Wind, elevation and temperature report as `WND`,
`ELEV` and `TEMP`; `AFM` is reserved for a missing chart figure and the
structural maximum weight. When no weight satisfies every constraint, the
maximum weight is `nil` and the report prints `N/A` with the factor that ruled
every weight out. When the limit rests on clamped figures, the report marks it
`offscale`, as it does a distance.

## Usage Example

```swift
// Create input from user configuration
let input = PerformanceInput(
    airport: airportInput,
    runway: runwayInput,
    conditions: conditions,
    weight: takeoffWeight,
    flapSetting: .flaps50,
    safetyFactor: 1.0,
    useRegressionModel: true,
    aircraftType: .g2Plus,
    emptyWeight: emptyWeight,
    date: Date()
)

// Fetch user-defined scenarios
let fetcher = ScenarioFetcher(modelContainer: container)
let scenarios = try await fetcher.fetchTakeoffScenarios()

// Generate report
let report = try generateTakeoffReport(input: input, scenarios: scenarios)
let pdf = try ReportPDF.render(html: report.html, documentTitle: report.documentTitle)
```

## See Also

- ``PerformanceInput``
- ``Report``
- ``ReportPDF``
- ``BaseReportData``
- ``TakeoffReportData``
- ``LandingReportData``
- ``BaseReportTemplate``
- ``generateTakeoffReport(input:scenarios:)``
- ``generateLandingReport(input:scenarios:)``
