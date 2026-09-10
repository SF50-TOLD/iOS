# ``SF50_Shared/Value``

## Topics

### Value Cases

- ``value(_:)``
- ``valueWithUncertainty(_:uncertainty:)``

### Error States

- ``invalid``
- ``notAvailable``
- ``notAuthorized``
- ``offscaleHigh(clamped:)``
- ``offscaleLow(clamped:)``

### Transformations

- ``map(_:)-((T)->U)``
- ``map(_:)-((T,T?)->(U,U?))``
- ``flatMap(_:)``

### Accessing Values

- ``nominal``
- ``nominalOrClamped``
- ``isOffscaleHigh``
- ``isOffscaleLow``
- ``toMeasurement(_:)``
