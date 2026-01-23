# Data Loading

Downloading and importing navigation data from GitHub.

## Overview

SF50 TOLD requires airport and runway data to calculate performance. This data
is pre-processed from FAA NASR and OurAirports sources, compressed, and hosted
on GitHub. The ``DataLoader`` actor downloads and imports this data into
SwiftData on first launch and when updates are available.

## Data Pipeline

![Airport Loading Pipeline](airport-loading-pipeline)

## Update Decision Logic

``DataLoaderViewModel`` determines when to show the loading UI based on:

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
becomes effective. If data isn't available yet, ``DataLoader`` throws
``DataLoader/Errors/cycleNotAvailable``.

## Loading Progress

The loader reports progress through the ``DataLoader/State`` enum:

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

## See Also

- ``DataLoader``
- ``DataLoaderViewModel``
