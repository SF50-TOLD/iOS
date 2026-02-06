# ``SF50_Shared/Conditions``

## Topics

### Creating Conditions

- ``init(windDirection:windSpeed:temperature:seaLevelPressure:)``
- ``init(observation:)``
- ``init(forecast:)``
- ``init()``

### Wind Properties

- ``windDirection``
- ``windSpeed``
- ``windsCalm``

### Temperature and Pressure

- ``temperature``
- ``dewpoint``
- ``seaLevelPressure``
- ``temperature(at:)``
- ``densityAltitude(elevation:)``

### Metadata

- ``validTime``
- ``source``
- ``Source``

### Combining Conditions

- ``adding(conditions:)``
- ``userModified(with:)``
