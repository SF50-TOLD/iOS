# Widget Architecture

Understanding the SF50 Runways widget's timeline-based data flow.

## Overview

The SF50 Runways widget uses WidgetKit's timeline architecture to display up-to-date takeoff or
landing performance for every runway at a chosen airport. This article explains how data flows
through the widget and how refreshes are triggered.

## Timeline-Based Updates

WidgetKit widgets don't run continuously—they provide snapshots of data at specific points in time.
The system calls into the widget to generate a timeline of entries, then displays those entries at
the appropriate times.

![Widget Architecture](widget-architecture)

## Key Components

### SelectedAirportConfigurationIntent

``SelectedAirportConfigurationIntent`` is what makes the widget configurable. It carries the airport,
the leg, and the landing flap setting, and the system presents it as the widget's edit sheet.

Every parameter's default reproduces the behavior the widget had before it was configurable: an empty
airport follows the app's own selection, and the leg defaults to takeoff. This matters because
WidgetKit hands a widget that is already on someone's home screen a default-initialized intent — a
default naming a specific airport would blank every widget already in use.

### TOLDProvider

``TOLDProvider`` implements `AppIntentTimelineProvider` and is the entry point for WidgetKit. It
responds to three requests:

1. **Placeholder**: An empty entry, drawn redacted while the widget loads
2. **Snapshot**: A fixed sample when WidgetKit asks for a gallery preview, so the card draws without
   waiting on the network; one real entry otherwise
3. **Timeline**: One entry with a refresh policy

```swift
func timeline(
    for configuration: SelectedAirportConfigurationIntent,
    in context: Context
) async -> Timeline<RunwayWidgetEntry> {
    .init(
        entries: [await entry(for: configuration)],
        policy: .after(Date().addingTimeInterval(900)) // 15 minutes
    )
}
```

### Where the numbers come from

The calculation itself is not in this target. `RunwayPerformanceService` in SF50 Shared loads the
airport from the shared app-group store, fetches current weather through `WeatherLoader`, and runs
`DefaultPerformanceCalculationService` over every runway — the same pipeline the app's own screens
use, and the same one the App Intents surfaces call. The provider's only job is to turn the result
into a ``RunwayWidgetEntry``.

### RunwayWidgetEntry

``RunwayWidgetEntry`` is a `TimelineEntry` that captures a snapshot of:

- The airport name and the leg being shown
- All runway snapshots (`RunwaySnapshot` from SF50 Shared)
- Weather conditions (`Conditions` from SF50 Shared)
- Calculated performance for each runway (`RunwayPerformance` from SF50 Shared)

## Data Sharing

The widget accesses the same data as the main app through:

1. **App Group Container**: SwiftData store at `group.codes.tim.TOLD`
2. **User Defaults**: Aircraft configuration via the Defaults library
3. **Shared Framework**: SF50 Shared provides weather loading and performance calculations

## Refresh Triggers

The widget refreshes in two scenarios:

### Scheduled Refresh

The timeline policy requests refresh every 15 minutes to capture weather changes. This is appropriate
for aviation weather which updates hourly (METAR) or every 6 hours (TAF).

### Settings Change

When the user changes settings in the main app (airport, weight, fuel), the app calls
`WidgetCenter.shared.reloadTimelines(ofKind:)` to trigger an immediate refresh.

## Empty States

The widget handles several empty states gracefully:

- **Nothing to show**: No airport selected, an airport that is no longer in the database, or a store
  that needs reimporting all render the same prompt to open the app
- **Weather unavailable**: Shows airport and runways without performance values
- **Calculation error**: Shows "N/A" for affected runways

## See Also

- ``SelectedAirportConfigurationIntent``
- ``TOLDProvider``
- ``RunwayWidgetEntry``
