# ``SF50_Shared/Runway``

## Topics

### Identification

- ``name``
- ``airport``
- ``reciprocal``

### Physical Properties

- ``elevation``
- ``trueHeading``
- ``magneticHeading``
- ``gradient``
- ``gradientOrBestGuess``
- ``length``
- ``isTurf``

### Declared Distances

- ``takeoffRun``
- ``takeoffRunOrLength``
- ``takeoffDistance``
- ``takeoffDistanceOrLength``
- ``landingDistance``
- ``landingDistanceOrLength``

### Distances a NOTAM Restricts

- ``availableTakeoffRun(notamedBy:)``
- ``availableTakeoffDistance(notamedBy:)``
- ``availableLandingDistance(notamedBy:)``

### Wind Calculations

- ``headwind(conditions:)``
- ``crosswind(conditions:)``
