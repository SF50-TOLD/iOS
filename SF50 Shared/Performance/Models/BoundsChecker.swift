import Foundation

/// Status of inputs relative to AFM table bounds.
///
/// Used by ``BoundsChecker`` to indicate whether performance calculation inputs
/// fall within, below, or above the valid data range.
enum BoundsStatus {
  /// All inputs are within the valid AFM table range.
  case withinBounds
  /// One or more inputs are below the minimum table value.
  case belowMinimum
  /// One or more inputs are above the maximum table value.
  case aboveMaximum
}

/// Validates performance calculation inputs against AFM data table bounds.
///
/// ``BoundsChecker`` is used by regression models to validate that inputs (weight,
/// altitude, temperature) fall within the ranges covered by the original AFM tables.
/// While regression models can extrapolate beyond these bounds, results outside the
/// valid range may be less reliable.
///
/// ## Usage
///
/// ```swift
/// let checker = BoundsChecker(aircraftType: .g1)
///
/// let status = checker.takeoffBoundsStatus(
///     weight: 5800,
///     altitude: 5000,
///     temperature: 30
/// )
///
/// if status == .aboveMaximum {
///     // Warn user that inputs exceed AFM data range
/// }
/// ```
final class BoundsChecker {

  private let takeoffRunData: DataTable
  private let landingRunData_flaps100: DataTable
  private let landingRunData_flaps50: DataTable
  private let landingRunData_flaps50Ice: DataTable
  private let enrouteClimbData_normal: [EnrouteClimbQuantity: DataTable]
  private let enrouteClimbData_iceContaminated: [EnrouteClimbQuantity: DataTable]

  init(aircraftType: AircraftType) {
    let loader = DataTableLoader(aircraftType: aircraftType)

    // Load takeoff data for bounds
    self.takeoffRunData = loader.loadTakeoffRunData()

    // Load landing data for each flap configuration
    self.landingRunData_flaps100 = loader.loadLandingRunData(landingPrefix: "100")
    self.landingRunData_flaps50 = loader.loadLandingRunData(landingPrefix: "50")
    self.landingRunData_flaps50Ice = loader.loadLandingRunData(landingPrefix: "50 ice")

    // Load en route climb data. Each quantity is bounded by its own table: under the
    // ice-contaminated schedule the rate is tabulated 2,000 ft higher and 2 °C colder than the
    // gradient, and bounding one by the other would refuse a figure the AFM does give.
    func enrouteClimbData(iceContaminated: Bool) -> [EnrouteClimbQuantity: DataTable] {
      [
        .gradient: loader.loadEnrouteClimbGradientData(iceContaminated: iceContaminated),
        .rate: loader.loadEnrouteClimbRateData(iceContaminated: iceContaminated),
        .speed: loader.loadEnrouteClimbSpeedData(iceContaminated: iceContaminated)
      ]
    }
    self.enrouteClimbData_normal = enrouteClimbData(iceContaminated: false)
    self.enrouteClimbData_iceContaminated = enrouteClimbData(iceContaminated: true)
  }

  /// Returns the bounds status for takeoff parameters.
  /// - Parameters:
  ///   - weight: Aircraft weight in lbs
  ///   - altitude: Pressure altitude in feet
  ///   - temperature: Temperature in Celsius
  /// - Returns: The bounds status (within, below, or above limits)
  func takeoffBoundsStatus(
    weight: Double,
    altitude: Double,
    temperature: Double
  ) -> BoundsStatus {
    checkBoundsStatus(
      weight: weight,
      altitude: altitude,
      temperature: temperature,
      dataTable: takeoffRunData
    )
  }

  /// Returns the bounds status for landing parameters.
  /// - Parameters:
  ///   - weight: Aircraft weight in lbs
  ///   - altitude: Pressure altitude in feet
  ///   - temperature: Temperature in Celsius
  ///   - flapSetting: The flap configuration to check bounds for
  /// - Returns: The bounds status (within, below, or above limits)
  func landingBoundsStatus(
    weight: Double,
    altitude: Double,
    temperature: Double,
    flapSetting: FlapSetting
  ) -> BoundsStatus {
    let dataTable: DataTable =
      switch flapSetting {
        case .flaps100: landingRunData_flaps100
        case .flaps50, .flapsUp: landingRunData_flaps50
        case .flaps50Ice, .flapsUpIce: landingRunData_flaps50Ice
      }

    return checkBoundsStatus(
      weight: weight,
      altitude: altitude,
      temperature: temperature,
      dataTable: dataTable
    )
  }

  /// Returns the bounds status for en route climb parameters.
  ///
  /// The regression's en route climb equations are fitted to these tables and turn nonsensical
  /// outside them — at the temperatures the Climb tab can ask for, the fitted gradient goes
  /// negative — so callers use this to refuse rather than to warn.
  ///
  /// - Parameters:
  ///   - quantity: Which en route climb figure is being asked for
  ///   - weight: Aircraft weight in lbs
  ///   - altitude: Pressure altitude in feet
  ///   - temperature: Temperature in Celsius
  ///   - iceContaminated: Whether the ice-contaminated schedule applies
  /// - Returns: The bounds status (within, below, or above limits)
  func enrouteClimbBoundsStatus(
    for quantity: EnrouteClimbQuantity,
    weight: Double,
    altitude: Double,
    temperature: Double,
    iceContaminated: Bool
  ) -> BoundsStatus {
    let tables = iceContaminated ? enrouteClimbData_iceContaminated : enrouteClimbData_normal
    guard let dataTable = tables[quantity] else {
      preconditionFailure("No en route climb table for \(quantity)")
    }

    return checkBoundsStatus(
      weight: weight,
      altitude: altitude,
      temperature: temperature,
      dataTable: dataTable,
      axes: .enrouteClimb
    )
  }

  // MARK: - Private Helpers

  private func checkBoundsStatus(
    weight: Double,
    altitude: Double,
    temperature: Double,
    dataTable: DataTable,
    axes: AxisOrder = .distance
  ) -> BoundsStatus {
    let inputs = [
      (value: weight, dimension: axes.weight),
      (value: altitude, dimension: axes.altitude),
      (value: temperature, dimension: axes.temperature)
    ]

    for (value, dimension) in inputs {
      if value < dataTable.min(dimension: dimension) {
        return .belowMinimum
      }
      if value > dataTable.max(dimension: dimension) {
        return .aboveMaximum
      }
    }

    // All parameters within bounds
    return .withinBounds
  }

  /// An en route climb figure, each tabulated over its own envelope.
  enum EnrouteClimbQuantity {
    case gradient
    case rate
    case speed
  }

  /// Which column of a table each input occupies.
  ///
  /// The AFM's own column order is not the same throughout: the distance tables lead with weight,
  /// the en route climb tables with pressure altitude.
  private struct AxisOrder {
    static let distance = Self(weight: 0, altitude: 1, temperature: 2),
      enrouteClimb = Self(weight: 2, altitude: 0, temperature: 1)

    let weight: Int,
      altitude: Int,
      temperature: Int
  }
}
