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
        indicatedAirspeedKts: takeoffClimbSpeedKIAS
      ),
      enrouteObstacle: .init(
        gradientFtPerNM: obstacleGradient,
        indicatedAirspeedKts: obstacleClimbSpeedKIAS
      ),
      enrouteObstacleAntiIce: .init(
        gradientFtPerNM: obstacleGradientIce,
        indicatedAirspeedKts: obstacleClimbSpeedKIAS
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
  private protocol EquationSource {
    func takeoffClimbGradient(weight: Double, altitude: Double, temperature: Double) -> Double
    func enrouteObstacleClimbGradient(
      weight: Double,
      altitude: Double,
      temperature: Double,
      iceContaminated: Bool
    ) -> Double
    func enrouteClimbGradient(
      weight: Double,
      altitude: Double,
      temperature: Double,
      iceContaminated: Bool
    ) -> Double
    func enrouteClimbSpeed(
      weight: Double,
      altitude: Double,
      temperature: Double,
      iceContaminated: Bool
    ) -> Double
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

    private func eval(
      _ eq: RegressionEquation,
      weight: Double,
      altitude: Double,
      temperature: Double
    ) -> Double {
      let result = eq.evaluate(inputs: [
        "weight": weight,
        "altitude": altitude,
        "temperature": temperature
      ])
      switch result {
        case .value(let v): return v
        case .valueWithUncertainty(let v, _): return v
        default: return .nan
      }
    }

    /// Evaluates a delta polynomial: result = base_value - max(0, delta_value).
    /// Falls back to regular evaluation if the equation is not a delta type.
    private func evalDelta(
      base: RegressionEquation,
      delta: RegressionEquation,
      weight: Double,
      altitude: Double,
      temperature: Double
    ) -> Double {
      guard delta.type == .deltaPolynomial else {
        return eval(delta, weight: weight, altitude: altitude, temperature: temperature)
      }
      let baseVal = eval(base, weight: weight, altitude: altitude, temperature: temperature)
      let deltaVal = eval(delta, weight: weight, altitude: altitude, temperature: temperature)
      return baseVal - max(0, deltaVal)
    }

    func takeoffClimbGradient(weight: Double, altitude: Double, temperature: Double) -> Double {
      eval(takeoffGradientEq, weight: weight, altitude: altitude, temperature: temperature)
    }

    func enrouteObstacleClimbGradient(
      weight: Double,
      altitude: Double,
      temperature: Double,
      iceContaminated: Bool
    ) -> Double {
      if iceContaminated {
        return evalDelta(
          base: obstacleGradientNormalEq,
          delta: obstacleGradientIceEq,
          weight: weight,
          altitude: altitude,
          temperature: temperature
        )
      }
      return eval(
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
    ) -> Double {
      let equation = iceContaminated ? enrouteGradientIceEq : enrouteGradientNormalEq
      return eval(equation, weight: weight, altitude: altitude, temperature: temperature)
    }

    func enrouteClimbSpeed(
      weight: Double,
      altitude: Double,
      temperature: Double,
      iceContaminated: Bool
    ) -> Double {
      let equation = iceContaminated ? enrouteSpeedIceEq : enrouteSpeedNormalEq
      return eval(equation, weight: weight, altitude: altitude, temperature: temperature)
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

    private func tableValue(_ table: DataTable, inputs: [Double]) -> Double {
      let result = table.value(for: inputs)
      switch result {
        case .value(let v): return v
        case .valueWithUncertainty(let v, _): return v
        default: return .nan
      }
    }

    private func regressionValue(
      _ eq: RegressionEquation,
      weight: Double,
      altitude: Double,
      temperature: Double
    ) -> Double {
      let result = eq.evaluate(inputs: [
        "weight": weight,
        "altitude": altitude,
        "temperature": temperature
      ])
      switch result {
        case .value(let v): return v
        case .valueWithUncertainty(let v, _): return v
        default: return .nan
      }
    }

    private func regressionDelta(
      base: RegressionEquation,
      delta: RegressionEquation,
      weight: Double,
      altitude: Double,
      temperature: Double
    ) -> Double {
      guard delta.type == .deltaPolynomial else {
        return regressionValue(delta, weight: weight, altitude: altitude, temperature: temperature)
      }
      let baseVal = regressionValue(
        base,
        weight: weight,
        altitude: altitude,
        temperature: temperature
      )
      let deltaVal = regressionValue(
        delta,
        weight: weight,
        altitude: altitude,
        temperature: temperature
      )
      return baseVal - max(0, deltaVal)
    }

    func takeoffClimbGradient(weight: Double, altitude: Double, temperature: Double) -> Double {
      // Takeoff table uses [weight, altitude, temperature]
      tableValue(takeoffGradientTable, inputs: [weight, altitude, temperature])
    }

    func enrouteObstacleClimbGradient(
      weight: Double,
      altitude: Double,
      temperature: Double,
      iceContaminated: Bool
    ) -> Double {
      // No tabular data for obstacle climb; fall back to regression
      if iceContaminated {
        return regressionDelta(
          base: obstacleGradientNormalEq,
          delta: obstacleGradientIceEq,
          weight: weight,
          altitude: altitude,
          temperature: temperature
        )
      }
      return regressionValue(
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
    ) -> Double {
      // Enroute tables use [altitude, temperature, weight]
      let table = iceContaminated ? enrouteGradientIceTable : enrouteGradientNormalTable
      return tableValue(table, inputs: [altitude, temperature, weight])
    }

    func enrouteClimbSpeed(
      weight: Double,
      altitude: Double,
      temperature: Double,
      iceContaminated: Bool
    ) -> Double {
      // Enroute tables use [altitude, temperature, weight]
      let table = iceContaminated ? enrouteSpeedIceTable : enrouteSpeedNormalTable
      return tableValue(table, inputs: [altitude, temperature, weight])
    }
  }
}
