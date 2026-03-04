# ``SF50_Shared``

Shared framework providing models, performance calculations, and data loading for SF50 TOLD.

## Overview

SF50 Shared is the core framework used by the SF50 TOLD app and its widget extension.
It provides:

- **Domain Models**: Airport, runway, weather conditions, and aircraft configuration types
- **Performance Calculations**: Takeoff and landing performance computation using AFM data
- **Data Loading**: Weather (METAR/TAF), NOTAM, and location services
- **Persistence**: SwiftData models for airport and runway data

## Topics

### Data Model

- <doc:AirportsAndNavigation>
- <doc:WeatherAndNOTAMs>
- <doc:AircraftConfiguration>

### Performance and Terrain

- <doc:PerformanceCalculations>
- <doc:TerrainAndClimbAnalysis>

### Support

- <doc:Utilities>
