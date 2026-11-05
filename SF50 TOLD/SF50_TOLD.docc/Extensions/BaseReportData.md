# ``SF50_TOLD/BaseReportData``

## Overview

``BaseReportData`` implements the Template Method design pattern for TLR
data generation. The base class provides the algorithm structure while
subclasses (``TakeoffReportData`` and ``LandingReportData``) implement
operation-specific calculations.

## Algorithm Flow

The ``generate()`` method orchestrates the calculation pipeline:

1. **Generate Runway Info**: For each runway, determine maximum weight and
   limiting factor using ``determineMaxWeight(runway:)``

2. **Generate Scenarios**: For each scenario, calculate performance for all
   runways using ``calculatePerformanceForAllRunways(scenario:)``

3. **Return Output**: Package results into ``ReportOutput``

## Maximum Weight

Each subclass's ``determineMaxWeight(runway:)`` runs the SF50Performance
package's limit search, which finds the highest weight that satisfies every
constraint (AFM limitations and chart limits, runway length, obstacle or climb
requirements). ``generateRunwayInfo()`` turns its result into the weight, the
``LimitingFactor`` and the offscale marker the report shows.

## Topics

### Generating Reports

- ``generate()``
- ``generateRunwayInfo()``
- ``generateScenarios()``
- ``calculatePerformanceForAllRunways(scenario:)``

### Template Methods

- ``operation()``
- ``calculatePerformance(for:conditions:config:)``
- ``determineMaxWeight(runway:)``
- ``createScenario(name:runways:)``
