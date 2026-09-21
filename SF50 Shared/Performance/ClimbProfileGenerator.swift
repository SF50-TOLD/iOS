import Foundation

/// Generates a ``ClimbProfile`` from weather observations, aircraft weight,
/// and performance equations/tables.
public enum ClimbProfileGenerator {

  /// Takeoff climb speed (Vx) in KIAS. Constant across all conditions.
  public static let takeoffClimbSpeedKIAS: Double = 91

  /// Enroute obstacle climb speed in KIAS. Constant across all conditions.
  public static let obstacleClimbSpeedKIAS: Double = 120

  /// Generates a climb profile by evaluating performance equations at each altitude
  /// in the provided winds-aloft observations.
  ///
  /// - Parameters:
  ///   - windsAloft: Atmospheric observations at various altitudes.
  ///   - weightLb: Aircraft weight in pounds.
  ///   - aircraftType: Aircraft variant (determines which equations/tables to load).
  ///   - seaLevelPressureInHg: Sea-level pressure for TAS computation.
  ///   - useRegressionModel: If true, use regression equations; otherwise use tabular data.
  /// - Returns: A ``ClimbProfile`` with data points at each winds-aloft altitude.
  public static func generate(
    windsAloft: [WindsAloftObservation],
    weightLb: Double,
    aircraftType: AircraftType,
    seaLevelPressureInHg: Double,
    useRegressionModel: Bool
  ) -> ClimbProfile {
    let source: any EquationSource
    if useRegressionModel {
      source = RegressionSource(aircraftType: aircraftType)
    } else {
      source = TabularSource(aircraftType: aircraftType)
    }

    let dataPoints = windsAloft.map { obs in
      makeDataPoint(obs: obs, weightLb: weightLb, source: source)
    }

    return ClimbProfile(dataPoints: dataPoints, seaLevelPressureInHg: seaLevelPressureInHg)
  }

  // MARK: - Private

  private static func makeDataPoint(
    obs: WindsAloftObservation,
    weightLb: Double,
    source: any EquationSource
  ) -> ClimbProfile.DataPoint {
    let altitude = obs.altitudeFt,
      temperature = obs.temperatureC

    // Takeoff climb gradient (no anti-ice variant)
    let takeoffGradient = source.takeoffClimbGradient(
      weight: weightLb,
      altitude: altitude,
      temperature: temperature
    )

    // Enroute obstacle climb gradients
    let obstacleGradient = source.enrouteObstacleClimbGradient(
      weight: weightLb,
      altitude: altitude,
      temperature: temperature,
      iceContaminated: false
    )
    let obstacleGradientIce = source.enrouteObstacleClimbGradient(
      weight: weightLb,
      altitude: altitude,
      temperature: temperature,
      iceContaminated: true
    )

    // Enroute climb gradients
    let enrouteGradient = source.enrouteClimbGradient(
      weight: weightLb,
      altitude: altitude,
      temperature: temperature,
      iceContaminated: false
    )
    let enrouteGradientIce = source.enrouteClimbGradient(
      weight: weightLb,
      altitude: altitude,
      temperature: temperature,
      iceContaminated: true
    )

    // Enroute climb speeds
    let enrouteSpeed = source.enrouteClimbSpeed(
      weight: weightLb,
      altitude: altitude,
      temperature: temperature,
      iceContaminated: false
    )
    let enrouteSpeedIce = source.enrouteClimbSpeed(
      weight: weightLb,
      altitude: altitude,
      temperature: temperature,
      iceContaminated: true
    )

    return ClimbProfile.DataPoint(
      altitudeFt: altitude,
      outsideAirTemperatureC: temperature,
      windDirectionDeg: obs.windDirectionDeg,
      windSpeedKts: obs.windSpeedKts,
      takeoff: .init(
        gradientFtPerNM: takeoffGradient,
        indicatedAirspeedKts: .value(takeoffClimbSpeedKIAS)
      ),
      enrouteObstacle: .init(
        gradientFtPerNM: obstacleGradient,
        indicatedAirspeedKts: .value(obstacleClimbSpeedKIAS)
      ),
      enrouteObstacleAntiIce: .init(
        gradientFtPerNM: obstacleGradientIce,
        indicatedAirspeedKts: .value(obstacleClimbSpeedKIAS)
      ),
      enroute: .init(
        gradientFtPerNM: enrouteGradient,
        indicatedAirspeedKts: enrouteSpeed
      ),
      enrouteAntiIce: .init(
        gradientFtPerNM: enrouteGradientIce,
        indicatedAirspeedKts: enrouteSpeedIce
      )
    )
  }

  /// Evaluates a regression equation at a weight, altitude and temperature.
  ///
  /// `RegressionEquation` already answers in `Value`; this only spells the inputs, which both
  /// sources name identically.
  private static func evaluate(
    _ equation: RegressionEquation,
    weight: Double,
    altitude: Double,
    temperature: Double
  ) -> Value<Double> {
    equation.evaluate(inputs: [
      "weight": weight,
      "altitude": altitude,
      "temperature": temperature
    ])
  }

  /// Evaluates a delta polynomial as `base - max(0, delta)`, or the equation itself where it is
  /// not a delta type.
  ///
  /// Where either half has no answer, neither has the difference — so the refusal is passed out
  /// rather than being allowed to read as a penalty of zero.
  private static func evaluateDelta(
    base: RegressionEquation,
    delta: RegressionEquation,
    weight: Double,
    altitude: Double,
    temperature: Double
  ) -> Value<Double> {
    guard delta.type == .deltaPolynomial else {
      return evaluate(delta, weight: weight, altitude: altitude, temperature: temperature)
    }

    let deltaValue = evaluate(delta, weight: weight, altitude: altitude, temperature: temperature)
    guard let penalty = deltaValue.nominal else { return deltaValue }
    return evaluate(base, weight: weight, altitude: altitude, temperature: temperature)
      - Swift.max(0, penalty)
  }

  /// A winds-aloft observation at a single altitude.
  public struct WindsAloftObservation: Sendable {
    public let altitudeFt: Double
    public let temperatureC: Double
    public let windDirectionDeg: Double  // true, FROM
    public let windSpeedKts: Double

    public init(
      altitudeFt: Double,
      temperatureC: Double,
      windDirectionDeg: Double,
      windSpeedKts: Double
    ) {
      self.altitudeFt = altitudeFt
      self.temperatureC = temperatureC
      self.windDirectionDeg = windDirectionDeg
      self.windSpeedKts = windSpeedKts
    }
  }

  // MARK: - Equation Sources

  /// Abstracts whether we use regression equations or data tables.
  ///
  /// Every figure is a `Value` because either source is entitled to have no answer, and which
  /// kind of no-answer it was matters downstream: conditions outside the charts read differently
  /// to a hole in them, and both read differently to an equation that could not be evaluated.
  private protocol EquationSource {
    func takeoffClimbGradient(weight: Double, altitude: Double, temperature: Double)
      -> Value<Double>
    func enrouteObstacleClimbGradient(
      weight: Double,
      altitude: Double,
      temperature: Double,
      iceContaminated: Bool
    ) -> Value<Double>
    func enrouteClimbGradient(
      weight: Double,
      altitude: Double,
      temperature: Double,
      iceContaminated: Bool
    ) -> Value<Double>
    func enrouteClimbSpeed(
      weight: Double,
      altitude: Double,
      temperature: Double,
      iceContaminated: Bool
    ) -> Value<Double>
  }

  // MARK: - Regression Source

  private struct RegressionSource: EquationSource {
    private let takeoffGradientEq: RegressionEquation
    private let obstacleGradientNormalEq: RegressionEquation
    private let obstacleGradientIceEq: RegressionEquation
    private let enrouteGradientNormalEq: RegressionEquation
    private let enrouteGradientIceEq: RegressionEquation
    private let enrouteSpeedNormalEq: RegressionEquation
    private let enrouteSpeedIceEq: RegressionEquation

    init(aircraftType: AircraftType) {
      let loader = RegressionEquationLoader(aircraftType: aircraftType)
      takeoffGradientEq = loader.loadTakeoffClimbGradientEquation()
      obstacleGradientNormalEq = loader.loadEnrouteObstacleClimbGradientEquation(
        iceContaminated: false
      )
      obstacleGradientIceEq = loader.loadEnrouteObstacleClimbGradientEquation(
        iceContaminated: true
      )
      enrouteGradientNormalEq = loader.loadEnrouteClimbGradientEquation(
        iceContaminated: false
      )
      enrouteGradientIceEq = loader.loadEnrouteClimbGradientEquation(iceContaminated: true)
      enrouteSpeedNormalEq = loader.loadEnrouteClimbSpeedEquation(iceContaminated: false)
      enrouteSpeedIceEq = loader.loadEnrouteClimbSpeedEquation(iceContaminated: true)
    }

    func takeoffClimbGradient(weight: Double, altitude: Double, temperature: Double)
      -> Value<Double>
    {
      evaluate(takeoffGradientEq, weight: weight, altitude: altitude, temperature: temperature)
    }

    func enrouteObstacleClimbGradient(
      weight: Double,
      altitude: Double,
      temperature: Double,
      iceContaminated: Bool
    ) -> Value<Double> {
      if iceContaminated {
        return evaluateDelta(
          base: obstacleGradientNormalEq,
          delta: obstacleGradientIceEq,
          weight: weight,
          altitude: altitude,
          temperature: temperature
        )
      }
      return evaluate(
        obstacleGradientNormalEq,
        weight: weight,
        altitude: altitude,
        temperature: temperature
      )
    }

    func enrouteClimbGradient(
      weight: Double,
      altitude: Double,
      temperature: Double,
      iceContaminated: Bool
    ) -> Value<Double> {
      let equation = iceContaminated ? enrouteGradientIceEq : enrouteGradientNormalEq
      return evaluate(equation, weight: weight, altitude: altitude, temperature: temperature)
    }

    func enrouteClimbSpeed(
      weight: Double,
      altitude: Double,
      temperature: Double,
      iceContaminated: Bool
    ) -> Value<Double> {
      let equation = iceContaminated ? enrouteSpeedIceEq : enrouteSpeedNormalEq
      return evaluate(equation, weight: weight, altitude: altitude, temperature: temperature)
    }
  }

  // MARK: - Tabular Source

  private struct TabularSource: EquationSource {
    private let takeoffGradientTable: DataTable
    private let enrouteGradientNormalTable: DataTable
    private let enrouteGradientIceTable: DataTable
    private let enrouteSpeedNormalTable: DataTable
    private let enrouteSpeedIceTable: DataTable
    // Obstacle climb: use regression even in tabular mode (no tabular data available)
    private let obstacleGradientNormalEq: RegressionEquation
    private let obstacleGradientIceEq: RegressionEquation

    init(aircraftType: AircraftType) {
      let tableLoader = DataTableLoader(aircraftType: aircraftType)
      let regressionLoader = RegressionEquationLoader(aircraftType: aircraftType)

      takeoffGradientTable = tableLoader.loadTakeoffClimbGradientData()
      enrouteGradientNormalTable = tableLoader.loadEnrouteClimbGradientData(
        iceContaminated: false
      )
      enrouteGradientIceTable = tableLoader.loadEnrouteClimbGradientData(
        iceContaminated: true
      )
      enrouteSpeedNormalTable = tableLoader.loadEnrouteClimbSpeedData(iceContaminated: false)
      enrouteSpeedIceTable = tableLoader.loadEnrouteClimbSpeedData(iceContaminated: true)

      obstacleGradientNormalEq = regressionLoader.loadEnrouteObstacleClimbGradientEquation(
        iceContaminated: false
      )
      obstacleGradientIceEq = regressionLoader.loadEnrouteObstacleClimbGradientEquation(
        iceContaminated: true
      )
    }

    /// Reads a table, and asks for no clamping.
    ///
    /// `DataTable` can hold an input at its low edge and hand back that edge's figure as the
    /// `clamped` payload of an offscale result, which is conservative and honest. Nothing here
    /// can carry it: the profile is read through `gradient(at:profile:)`, which answers in a bare
    /// `Double`, so a substituted figure would arrive at the climb integration indistinguishable
    /// from one the chart covered. Until a readout can say a figure came from the edge of a
    /// chart, the table is asked only for what it actually holds.
    private func tableValue(_ table: DataTable, inputs: [Double]) -> Value<Double> {
      table.value(for: inputs)
    }

    func takeoffClimbGradient(weight: Double, altitude: Double, temperature: Double)
      -> Value<Double>
    {
      // Takeoff table uses [weight, altitude, temperature]
      tableValue(takeoffGradientTable, inputs: [weight, altitude, temperature])
    }

    func enrouteObstacleClimbGradient(
      weight: Double,
      altitude: Double,
      temperature: Double,
      iceContaminated: Bool
    ) -> Value<Double> {
      // No tabular data for obstacle climb; fall back to regression
      if iceContaminated {
        return evaluateDelta(
          base: obstacleGradientNormalEq,
          delta: obstacleGradientIceEq,
          weight: weight,
          altitude: altitude,
          temperature: temperature
        )
      }
      return evaluate(
        obstacleGradientNormalEq,
        weight: weight,
        altitude: altitude,
        temperature: temperature
      )
    }

    func enrouteClimbGradient(
      weight: Double,
      altitude: Double,
      temperature: Double,
      iceContaminated: Bool
    ) -> Value<Double> {
      // Enroute tables use [altitude, temperature, weight]
      let table = iceContaminated ? enrouteGradientIceTable : enrouteGradientNormalTable
      return tableValue(table, inputs: [altitude, temperature, weight])
    }

    func enrouteClimbSpeed(
      weight: Double,
      altitude: Double,
      temperature: Double,
      iceContaminated: Bool
    ) -> Value<Double> {
      // Enroute tables use [altitude, temperature, weight]
      let table = iceContaminated ? enrouteSpeedIceTable : enrouteSpeedNormalTable
      return tableValue(table, inputs: [altitude, temperature, weight])
    }
  }
}
