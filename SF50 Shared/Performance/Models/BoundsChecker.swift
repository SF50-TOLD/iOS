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

  init(aircraftType: AircraftType) {
    let loader = DataTableLoader(aircraftType: aircraftType)

    // Load takeoff data for bounds
    self.takeoffRunData = loader.loadTakeoffRunData()

    // Load landing data for each flap configuration
    self.landingRunData_flaps100 = loader.loadLandingRunData(landingPrefix: "100")
    self.landingRunData_flaps50 = loader.loadLandingRunData(landingPrefix: "50")
    self.landingRunData_flaps50Ice = loader.loadLandingRunData(landingPrefix: "50 ice")
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

  // MARK: - Private Helpers

  private func checkBoundsStatus(
    weight: Double,
    altitude: Double,
    temperature: Double,
    dataTable: DataTable
  ) -> BoundsStatus {
    let inputs = [weight, altitude, temperature]

    // Check each dimension (weight=0, altitude=1, temperature=2)
    for dimension in 0..<3 {
      let input = inputs[dimension]
      let minValue = dataTable.min(dimension: dimension)
      let maxValue = dataTable.max(dimension: dimension)

      if input < minValue {
        return .belowMinimum
      }
      if input > maxValue {
        return .aboveMaximum
      }
    }

    // All parameters within bounds
    return .withinBounds
  }
}
