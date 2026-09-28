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

Downloaded NOTAMs are read into proposals for the pilot to confirm: formatted
reports by deterministic parsers, everything else by the on-device model when
its asset pack is installed. Confirming one NOTAM's proposal fills the NOTAM
editor in with ``NOTAMProposal/fill(_:for:)``, which can be undone.

- ``NOTAMProposer``
- ``NOTAMProposal``
- ``NOTAMRestoration``
- ``NOTAMProposalMapper``
- ``ProposalRunway``
- ``Candidate``
- ``ProposalSource``
- ``NOTAMExtractor``
- ``NOTAMModelPack``
- ``NOTAMModelDigest``

### NOTAM API Types

- ``NOTAMListResponse``
- ``NOTAMResponse``
- ``NOTAMErrorResponse``
- ``QLine``
