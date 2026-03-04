# Performance Calculation Overview

Understanding how SF50 TOLD calculates aircraft performance.

## Overview

SF50 TOLD calculates takeoff and landing performance using data from the SF50 Vision Jet
Aircraft Flight Manual (AFM). The calculation pipeline transforms atmospheric conditions,
aircraft configuration, and runway data into distances, speeds, and climb rates, with
environmental and operational adjustments tracked as an auditable breakdown.

![Performance Calculation Pipeline](performance-calculation-pipeline)

## Pipeline Stages

The pipeline has four stages: **input collection**, **model selection**,
**model computation**, and **operational adjustments**. The first three happen inside
the ``PerformanceModel`` layer, while the last happens in
``DefaultPerformanceCalculationService``.

### 1. Input Collection

Four input types capture the conditions of the calculation:

| Type | Role |
|------|------|
| ``Conditions`` | Temperature, pressure altitude, wind direction and speed |
| ``Configuration`` | Aircraft weight and flap setting |
| ``RunwayInput`` | Elevation, gradient, surface type, declared distances |
| ``NOTAMInput`` | Runway contamination (RwyCC or contaminant type/depth) |

### 2. Model Selection

``DefaultPerformanceCalculationService/createPerformanceModel(conditions:configuration:runway:notam:useRegressionModel:aircraftType:)``
selects a concrete ``PerformanceModel`` based on the user's aircraft generation and
model preference (tabular or regression).

### 3. Model Computation

``BasePerformanceModel/computeDistance(for:)`` orchestrates the core calculation:

1. **Base value** — ``BasePerformanceModel/baseValue(for:)`` returns the unadjusted
   distance from regression equations or AFM table interpolation, depending on the
   concrete model.
2. **Adjustment selection** — ``PerformanceAdjustmentGenerator`` inspects the current
   conditions and returns an ordered list of ``AdjustmentKind`` values applicable to the
   ``DistanceTarget``.
3. **Adjustment application** — For each kind, ``BasePerformanceModel/applyAdjustment(_:to:target:)``
   computes the model-specific multiplier and updates the running total.

Each step is recorded as a ``PerformanceAdjustment`` in a ``DistanceBreakdown``, creating
an audit trail from the base distance to the final adjusted value.

#### Adjustment Order

``PerformanceAdjustmentGenerator`` enforces a fixed order. Not every adjustment applies
to every target:

| Adjustment | Takeoff Run | Takeoff Distance | Landing Run | Landing Distance |
|------------|:-----------:|:----------------:|:-----------:|:----------------:|
| Contamination | | | 1st | 1st |
| Headwind / Tailwind | 1st | 1st | 2nd | 2nd |
| Gradient (up/down) | 2nd | | 3rd | |
| Unpaved Surface | | 2nd | | 3rd |

Contamination is applied first for landing because AC 91-79B contamination factors
are defined relative to the unfactored AFM landing distance.

### 4. Operational Adjustments

After the model returns its result, ``DefaultPerformanceCalculationService`` layers on
two additional multiplicative adjustments. These are separated from the model because
they are pilot or operator decisions, not aircraft performance characteristics:

- **VREF Additive** (landing only) — Per AC 91-79B section 5.2.2, each 10% increase in
  VREF adds 20% to landing distance. The factor is `1 + 2 * (additiveKts / baseVrefKts)`.
- **Safety Factor** — A user-configured multiplier (e.g., 1.25 for a 25% margin).

These adjustments are appended to the model's ``DistanceBreakdown`` so the full chain
is visible in the UI.

#### Why Separate from the Model?

All multiplicative adjustments are commutative, so the mathematical result is the same
regardless of where they are applied. The separation is architectural: the model computes
*what the airplane will do* given environmental conditions, and the service layers on
*what we plan for* based on operational policy. Safety factor and VREF additive are
identical across all aircraft types and do not belong in the model-specific code.

## Performance Model Hierarchy

![Performance Model Hierarchy](performance-model-hierarchy)

``PerformanceModel`` is the protocol. ``BasePerformanceModel`` provides the shared
`computeDistance(for:)` loop. Subclasses only need to override two methods:

- ``BasePerformanceModel/baseValue(for:)`` — the unadjusted distance
- ``BasePerformanceModel/adjustmentMultiplier(for:target:)`` — model-specific multipliers

### Tabular Models

`TabularPerformanceModel` interpolates directly from digitized AFM performance charts.
It inherits from ``BasePerformanceModel`` and looks up values using multi-dimensional
table interpolation (weight, temperature, altitude). The `aircraftType` parameter
drives which data files are loaded.

### Regression Models

`RegressionPerformanceModel` uses curve-fitted polynomial equations derived from the
same AFM data. It produces smoother results across the input domain and carries
uncertainty estimates. The `aircraftType` parameter selects the JSON equation files,
which contain all variant-specific coefficients and adjustment factors.

## Distance Breakdown

``DistanceBreakdown`` captures the complete adjustment chain for a single distance
value. It stores the ``DistanceBreakdown/baseFt`` and an ordered array of
``PerformanceAdjustment`` entries. Each entry records:

- ``PerformanceAdjustment/kind`` — which adjustment (e.g., `.headwind`, `.contamination`)
- ``PerformanceAdjustment/multiplier`` — the effective multiplier at that step
- ``PerformanceAdjustment/resultFt`` — the running total after the adjustment

This allows the UI to display a step-by-step buildup from the base AFM distance to
the final operational distance.

### Example Breakdown

A landing distance calculation might produce:

| Step | Adjustment | Multiplier | Result |
|------|-----------|:----------:|-------:|
| Base | — | — | 2,000 ft |
| 1 | Contamination (wet) | 1.15 | 2,300 ft |
| 2 | Headwind 10 kt | 0.95 | 2,185 ft |
| 3 | Uphill 1% | 1.05 | 2,294 ft |
| 4 | VREF +5 kt | 1.10 | 2,524 ft |
| 5 | Safety factor 1.25 | 1.25 | 3,155 ft |

## Handling Uncertainty

Performance values are wrapped in ``Value`` to represent:

- **Definite values** — ``Value/value(_:)`` for exact results (tabular models)
- **Values with uncertainty** — ``Value/valueWithUncertainty(_:uncertainty:)`` for
  regression results with statistical confidence intervals
- **Error states** — ``Value/invalid``, ``Value/notAvailable``, ``Value/notAuthorized``,
  ``Value/offscaleHigh``, ``Value/offscaleLow``

The ``Value`` wrapper propagates through arithmetic operations (multiplication, addition)
and the ``Value/toMeasurement(_:)`` conversion, preserving uncertainty from base value
through every adjustment to the final result.

## Output Types

The service returns ``TakeoffReport`` or ``LandingReport``, each containing:

- **Results** (``TakeoffResults`` or ``LandingResults``) — final performance values
  converted to `Measurement` types with units
- **Ground run breakdown** — ``DistanceBreakdown`` for the run distance
- **Distance breakdown** — ``DistanceBreakdown`` for the total distance (to 35 ft AGL
  for takeoff, from 50 ft AGL for landing)

## Using the Service

```swift
let service = DefaultPerformanceCalculationService.shared

let model = service.createPerformanceModel(
    conditions: conditions,
    configuration: configuration,
    runway: runway,
    notam: notam,
    useRegressionModel: true,
    aircraftType: .g2Plus
)

let takeoff = try service.calculateTakeoff(for: model, safetyFactor: 1.25)
let landing = try service.calculateLanding(
    for: model, safetyFactor: 1.25, VREFAdditiveKts: 5
)

// Inspect the adjustment chain
for adjustment in landing.distanceBreakdown.adjustments {
    print("\(adjustment.kind.localizedDescription): ×\(adjustment.multiplier)")
}
```

## See Also

- ``PerformanceCalculationService``
- ``DefaultPerformanceCalculationService``
- ``PerformanceModel``
- ``BasePerformanceModel``
- ``PerformanceAdjustmentGenerator``
- ``AdjustmentKind``
- ``PerformanceAdjustment``
- ``DistanceBreakdown``
- ``TakeoffReport``
- ``LandingReport``
- ``TakeoffResults``
- ``LandingResults``
- ``Value``
