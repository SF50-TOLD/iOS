# ``SF50_Shared/PerformanceModel``

## Topics

### Input Data

- ``conditions``
- ``configuration``
- ``runway``
- ``notam``

### Takeoff Performance

- ``takeoffRunFt``
- ``takeoffDistanceFt``
- ``takeoffClimbGradientFtNM``
- ``takeoffClimbRateFtMin``

### En Route Climb Performance

- ``enrouteClimbGradientFtNM``
- ``enrouteClimbRateFtMin``
- ``enrouteClimbSpeedKIAS``
- ``enrouteObstacleClimbGradientFtNM``
- ``enrouteObstacleClimbRateFtMin``

### Landing Performance

- ``VrefKts``
- ``landingRunFt``
- ``landingDistanceFt``
- ``meetsGoAroundClimbGradient``

### Bounds Checking

- ``takeoffInputsOffscaleLow``
- ``takeoffInputsOffscaleHigh``
- ``landingInputsOffscaleLow``
- ``landingInputsOffscaleHigh``

### Distance Computation

- ``computeDistance(for:)``
