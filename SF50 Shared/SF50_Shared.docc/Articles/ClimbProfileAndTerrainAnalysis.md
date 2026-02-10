# Climb Profile and Terrain Analysis

Generating a climb performance profile, projecting it along an instrument procedure, and overlaying terrain and obstacle data.

## Overview

SF50 TOLD analyzes obstacle clearance along departure and missed-approach paths through a three-stage pipeline. First, `ClimbProfileGenerator` distills winds-aloft observations and aircraft weight into altitude-varying climb gradients and speeds. Then `ProcedurePathGenerator` steps through the legs of an instrument procedure, using the climb profile and wind data to produce a geographic flight path with altitudes. Finally, `ProcedureTerrainPathGenerator` enriches that path with terrain elevations and obstacle heights sampled across a lateral corridor, producing a `ProcedureTerrainPath` ready for display.

## Stage 1: Generating a Climb Profile

`ClimbProfileGenerator` is a stateless enum that accepts winds-aloft observations, aircraft weight, aircraft type, and sea-level pressure, and returns a `ClimbProfile`.

### Inputs

Each `ClimbProfileGenerator/WindsAloftObservation` supplies temperature, wind direction, and wind speed at a given altitude. The generator evaluates climb performance equations at every observed altitude using either regression curves or tabular AFM data (selected by the `useRegressionModel` flag).

### Climb Schedules

At each altitude the generator computes five independent climb schedules. All five are included in every `ClimbProfile`, and consumers select which schedule to use for each segment of the climb via `ClimbProfile/ProfileType`:

| Schedule                    | Speed                   | Anti-Ice |
| --------------------------- | ----------------------- | -------- |
| Takeoff                     | 91 KIAS (V<sub>X</sub>) | Off      |
| Enroute obstacle            | 120 KIAS                | Off      |
| Enroute obstacle (anti-ice) | 120 KIAS                | On       |
| Enroute                     | Best rate               | Off      |
| Enroute (anti-ice)          | Best rate               | On       |

### Output

The resulting `ClimbProfile` stores an array of `ClimbProfile/DataPoint` values sorted by altitude. Each data point carries the atmospheric conditions plus a `ClimbProfile/ClimbData` (gradient in ft/NM and indicated airspeed) for every schedule. The profile provides interpolation methods — `ClimbProfile/gradient(at:profile:)` and `ClimbProfile/trueAirspeed(at:profile:)` — that linearly interpolate between data points for any intermediate altitude, and integration methods — `ClimbProfile/altitude(after:from:profile:)` and `ClimbProfile/distance(from:to:profile:)` — that use trapezoidal integration over small steps to account for the altitude-varying gradient.

## Stage 2: Building a Procedure Path

`ProcedurePathGenerator` converts a sequence of instrument procedure legs into a geographic flight path with computed altitudes. It is initialized with a climb profile, climb schedule, and magnetic variation, then offers two entry points:

- `ProcedurePathGenerator/departurePath(from:takeoffPoint:takeoffPointAltitudeFt:)`
- `ProcedurePathGenerator/missedApproachPath(from:startCoordinate:startAltitudeFt:)`

### Leg Resolution

Each `Leg` carries a `LegType` describing its geometry — course to fix, heading to altitude, arc to fix, and so on. The generator maps each leg to an internal strategy (fix-terminated, altitude-terminated, DME-terminated, arc, etc.) that knows how to step along it. Legs that cannot be plotted (e.g., holds or procedure turns that aren't the final leg) cause the generator to return `nil`.

### Step Engine

The generator advances along each leg in **0.1 NM ground-distance steps**, up to a safety limit of 1,000 steps per leg. At each step:

1. The current altitude is integrated from the climb profile using a trapezoidal rule over the step distance.
2. Wind correction is applied depending on navigation mode: _course_ mode maintains a fixed ground track, while _heading_ mode flies a fixed magnetic heading and lets wind drift the track.
3. The new geographic position is projected forward from the previous point.
4. The step terminates when its leg-specific condition is met (reaching a fix, altitude, DME, or distance).

### Output

The result is a `ProcedurePath` — an array of `ProcedurePath/Point` values, each carrying a coordinate, cumulative distance from the origin, computed aircraft altitude, and optional fix name and altitude restriction.

## Stage 3: Enriching with Terrain and Obstacles

`ProcedureTerrainPathGenerator` takes a `ProcedurePath` and overlays terrain and obstacle data, producing a `ProcedureTerrainPath`. The generator samples terrain elevation and queries `Obstacle` records from SwiftData within a lateral corridor (default 0.25 NM wide) centered on the flight path. Generation is asynchronous.

Each `ProcedureTerrainPath/Point` extends the flight path with two optional fields: `terrainElevationFt` (the maximum terrain elevation across the corridor at that point) and `maxObstacleHeightFt` (the tallest obstacle within the corridor). Either field is `nil` when data is not available.

### Data Availability

Terrain and obstacle data may not cover the entire path. Two computed properties summarize coverage:

- `ProcedureTerrainPath/terrainDataAvailable` — `true` when every point has a terrain elevation. Points over ocean are filled to sea level automatically; points within an unloaded terrain region remain `nil`.
- `ProcedureTerrainPath/obstacleDataAvailable` — `true` when the entire path falls within the FAA Digital Obstacle File survey area, as determined by `ObstacleSurveyRegion`.

## Complete Example

```swift
// Stage 1: Build a climb profile from winds-aloft observations
let climbProfile = ClimbProfileGenerator.generate(
    windsAloft: observations,
    weightLb: 6000,
    aircraftType: .g2Plus,
    seaLevelPressureInHg: 29.92,
    useRegressionModel: true
)

// Stage 2: Project the departure procedure onto a geographic path
let pathGenerator = ProcedurePathGenerator(
    climbProfile: climbProfile,
    schedule: .init(firstSegment: .enrouteObstacle(antiIce: false)),
    magneticVariation: magneticVariation
)
guard let path = pathGenerator.departurePath(
    from: departure.legs,
    takeoffPoint: runwayEnd,
    takeoffPointAltitudeFt: fieldElevation
) else { return }

// Stage 3: Enrich with terrain and obstacle data
let generator = ProcedureTerrainPathGenerator(modelContainer: container)
let terrainPath = await generator.generate(from: path)

// Use the result
for point in terrainPath.points {
    let clearance = point.terrainElevationFt.map {
        point.aircraftAltitudeFt - $0
    }
    // Display terrain clearance profile...
}
```

## See Also

- `ClimbProfileGenerator`
- `ClimbProfile`
- `ProcedurePathGenerator`
- `ProcedurePath`
- `ProcedureTerrainPathGenerator`
- `ProcedureTerrainPath`
- `ObstacleSurveyRegion`
- `Obstacle`
- <doc:DigitalElevationModel>
