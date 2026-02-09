import Foundation

/// Loads regression equations from bundled JSON files.
///
/// ``RegressionEquationLoader`` provides methods to load regression equation
/// definitions for performance calculations. Each equation is stored as a
/// JSON file in the app bundle, organized by model type and category.
///
/// ## Data Organization
///
/// Equation files are organized in the bundle as:
///
/// ```
/// Data/
/// ├── g1/
/// │   └── regressions/
/// │       ├── takeoff-ground-run.json
/// │       ├── takeoff-total-distance.json
/// │       ├── vref-flaps50.json
/// │       └── ...
/// ├── g2/
/// │   └── regressions/
/// │       └── ...
/// └── g2+/
///     └── regressions/
///         └── ...
/// ```
///
struct RegressionEquationLoader {

  private let bundle: Bundle
  let aircraftType: AircraftType

  private var dataURL: URL {
    let directory = "Data/\(aircraftType.dataDirectoryName)/regressions"
    return bundle.resourceURL!.appending(component: directory, directoryHint: .isDirectory)
  }

  init(bundle: Bundle = Bundle(for: BasePerformanceModel.self), aircraftType: AircraftType) {
    self.bundle = bundle
    self.aircraftType = aircraftType
  }

  // MARK: - Takeoff Equations

  func loadTakeoffRunEquation() -> RegressionEquation {
    loadEquation(filename: "takeoff-ground-run.json")
  }

  func loadTakeoffDistanceEquation() -> RegressionEquation {
    loadEquation(filename: "takeoff-total-distance.json")
  }

  func loadTakeoffClimbGradientEquation() -> RegressionEquation {
    loadEquation(filename: "takeoff-climb-gradient.json")
  }

  func loadTakeoffClimbRateEquation() -> RegressionEquation {
    loadEquation(filename: "takeoff-climb-rate.json")
  }

  // MARK: - Takeoff Adjustment Factor Equations

  func loadTakeoffRunHeadwindFactorEquation() -> RegressionEquation {
    loadEquation(filename: "takeoff-run-headwind-factor.json")
  }

  func loadTakeoffRunTailwindFactorEquation() -> RegressionEquation {
    loadEquation(filename: "takeoff-run-tailwind-factor.json")
  }

  func loadTakeoffRunUphillFactorEquation() -> RegressionEquation {
    loadEquation(filename: "takeoff-run-uphill-factor.json")
  }

  func loadTakeoffRunDownhillFactorEquation() -> RegressionEquation {
    loadEquation(filename: "takeoff-run-downhill-factor.json")
  }

  func loadTakeoffDistanceHeadwindFactorEquation() -> RegressionEquation {
    loadEquation(filename: "takeoff-distance-headwind-factor.json")
  }

  func loadTakeoffDistanceTailwindFactorEquation() -> RegressionEquation {
    loadEquation(filename: "takeoff-distance-tailwind-factor.json")
  }

  func loadTakeoffDistanceUnpavedFactorEquation() -> RegressionEquation {
    loadEquation(filename: "takeoff-distance-unpaved-factor.json")
  }

  // MARK: - Landing Equations

  func loadLandingRunEquation(flapSetting: FlapSetting) -> RegressionEquation {
    let filename = "landing-run-\(flapSetting.regressionFileSuffix).json"
    return loadEquation(filename: filename)
  }

  func loadLandingDistanceEquation(flapSetting: FlapSetting) -> RegressionEquation {
    let filename = "landing-distance-\(flapSetting.regressionFileSuffix).json"
    return loadEquation(filename: filename)
  }

  func loadGoAroundClimbGradientEquation() -> RegressionEquation {
    loadEquation(filename: "go-around-climb-gradient.json")
  }

  // MARK: - Landing Adjustment Factor Equations

  func loadLandingRunHeadwindFactorEquation(flapSetting: FlapSetting) -> RegressionEquation {
    let filename = "landing-run-headwind-factor-\(flapSetting.regressionFileSuffix).json"
    return loadEquation(filename: filename)
  }

  func loadLandingRunTailwindFactorEquation(flapSetting: FlapSetting) -> RegressionEquation {
    let filename = "landing-run-tailwind-factor-\(flapSetting.regressionFileSuffix).json"
    return loadEquation(filename: filename)
  }

  func loadLandingRunUphillFactorEquation(flapSetting: FlapSetting) -> RegressionEquation {
    let filename = "landing-run-uphill-factor-\(flapSetting.regressionFileSuffix).json"
    return loadEquation(filename: filename)
  }

  func loadLandingRunDownhillFactorEquation() -> RegressionEquation {
    loadEquation(filename: "landing-run-downhill-factor.json")
  }

  func loadLandingDistanceHeadwindFactorEquation(
    flapSetting: FlapSetting
  ) -> RegressionEquation {
    let filename = "landing-distance-headwind-factor-\(flapSetting.regressionFileSuffix).json"
    return loadEquation(filename: filename)
  }

  func loadLandingDistanceTailwindFactorEquation(
    flapSetting: FlapSetting
  ) -> RegressionEquation {
    let filename = "landing-distance-tailwind-factor-\(flapSetting.regressionFileSuffix).json"
    return loadEquation(filename: filename)
  }

  func loadLandingDistanceUnpavedFactorEquation() -> RegressionEquation {
    loadEquation(filename: "landing-distance-unpaved-factor.json")
  }

  // MARK: - Vref Equations

  func loadVrefEquation(flapSetting: FlapSetting) -> RegressionEquation {
    let filename = "vref-\(flapSetting.regressionFileSuffix).json"
    return loadEquation(filename: filename)
  }

  // MARK: - En Route Climb Equations

  func loadEnrouteClimbGradientEquation(iceContaminated: Bool) -> RegressionEquation {
    let suffix = iceContaminated ? "ice" : "normal"
    return loadEquation(filename: "enroute-climb-gradient-\(suffix).json")
  }

  func loadEnrouteClimbRateEquation(iceContaminated: Bool) -> RegressionEquation {
    let suffix = iceContaminated ? "ice" : "normal"
    return loadEquation(filename: "enroute-climb-rate-\(suffix).json")
  }

  func loadEnrouteClimbSpeedEquation(iceContaminated: Bool) -> RegressionEquation {
    let suffix = iceContaminated ? "ice" : "normal"
    return loadEquation(filename: "enroute-climb-speed-\(suffix).json")
  }

  // MARK: - En Route Obstacle Climb Equations

  func loadEnrouteObstacleClimbGradientEquation(iceContaminated: Bool) -> RegressionEquation {
    let suffix = iceContaminated ? "ice" : "normal"
    return loadEquation(filename: "enroute-obstacle-climb-gradient-\(suffix).json")
  }

  func loadEnrouteObstacleClimbRateEquation(iceContaminated: Bool) -> RegressionEquation {
    let suffix = iceContaminated ? "ice" : "normal"
    return loadEquation(filename: "enroute-obstacle-climb-rate-\(suffix).json")
  }

  // MARK: - Private Helpers

  private func loadEquation(filename: String) -> RegressionEquation {
    let url = dataURL.appending(path: filename)
    do {
      return try RegressionEquation(fileURL: url)
    } catch {
      fatalError("Failed to load bundled regression equation \(filename): \(error)")
    }
  }
}

// MARK: - FlapSetting Extension

extension FlapSetting {
  /// The file suffix used for regression equation JSON files.
  var regressionFileSuffix: String {
    switch self {
      case .flapsUp: "flapsup"
      case .flapsUpIce: "flapsupice"
      case .flaps50: "flaps50"
      case .flaps50Ice: "flaps50ice"
      case .flaps100: "flaps100"
    }
  }

  /// Whether this flap setting is ice-contaminated.
  var isIceContaminated: Bool {
    switch self {
      case .flapsUpIce, .flaps50Ice: true
      default: false
    }
  }
}
