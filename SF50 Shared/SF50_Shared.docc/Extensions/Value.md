# ``SF50_Shared/Value``

## Topics

### Value Cases

- ``value(_:)``
- ``valueWithUncertainty(_:uncertainty:)``

### Error States

- ``invalid``
- ``notAvailable``
- ``notAuthorized``
- ``offscaleHigh``
- ``offscaleLow``

### Transformations

- ``map(_:)-((T)->U)``
- ``map(_:)-((T,T?)->(U,U?))``
- ``flatMap(_:)``
