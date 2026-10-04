# Weather and NOTAMs

Weather observation loading, atmospheric condition modeling, and NOTAM-based runway state tracking.

## Topics

### Essentials

- <doc:WeatherAndConditions>

### Atmospheric Conditions

- ``Conditions``
- ``WeatherLoader``
- ``WeatherLoaderProtocol``
- ``WeatherViewModel``

### Winds Aloft

- ``WindsAloftData``
- ``WindsAloftForecast``
- ``WindsAloftInterpolator``
- ``WindsAloftStation``

### NOTAMs

- ``NOTAM``
- ``Contamination``
- ``ShorteningLocation``
- ``NOTAMLoader``
- ``NOTAMCache``

### Reading NOTAMs

Downloaded NOTAMs in a fixed report format — runway condition reports and FAA
obstacle reports — are read into proposals for the pilot to confirm.
Confirming one NOTAM's proposal fills the NOTAM editor in with
``NOTAMProposal/fill(_:for:)``, which can be undone.

- ``NOTAMProposal``
- ``ProposedObstacle``
- ``ProposalRunway``
- ``NOTAMRestoration``
- ``Candidate``

### NOTAM API Types

- ``NOTAMListResponse``
- ``NOTAMResponse``
- ``NOTAMErrorResponse``
- ``QLine``
