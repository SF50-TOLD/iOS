# ``SF50_RunwaysExtension``

Widget extension displaying takeoff or landing performance for every runway at a chosen airport.

## Overview

SF50 Runways is a WidgetKit extension that shows at-a-glance performance data for an airport of the
reader's choosing. It displays:

- Airport name and weather conditions
- All runways with wind components
- Calculated distances against the distance available, or whether the leg is possible at all

The airport, the leg, and the landing flap setting are configured on the widget itself, so a
departure widget and an arrival widget can sit side by side. The widget refreshes every 15 minutes to
capture weather changes and uses the same performance calculation engine as the main app.

## Architecture

The widget follows a standard WidgetKit architecture:

1. **SelectedAirportConfigurationIntent**: Carries the reader's choices
2. **TOLDProvider**: Supplies timeline entries on demand
3. **RunwayWidgetEntry**: Snapshot of data at a point in time
4. **SelectedAirportWidgetEntryView**: Renders the entry

The calculation itself lives in `RunwayPerformanceService` in SF50 Shared, which the App Intents
surfaces in the main app share.

## Topics

### Widget Architecture

- <doc:WidgetArchitecture>
- ``SelectedAirportPerformanceWidget``
- ``SelectedAirportConfigurationIntent``
- ``TOLDProvider``
- ``RunwayWidgetEntry``
