import Foundation

/// Calculates landing distance increases due to runway contamination.
///
/// ``ContaminationCalculator`` adjusts landing ground run distances when runways are
/// contaminated with water, slush, or snow. The AFM provides specific adjustment factors
/// for different contamination types and depths.
///
/// ## Supported Contamination Types
///
/// - **Water or slush**: Standing water up to specified depth
/// - **Slush or wet snow**: Depth-dependent adjustment
/// - **Dry snow**: Fixed percentage increase
/// - **Compact snow**: Fixed percentage increase (largest impact)
/// - **Wet runway**: Fixed percentage increase
///
/// ## Calculation Methods
///
/// Two calculation approaches are supported based on initialization:
///
/// 1. **Tabular**: Uses ``DataTable`` interpolation for exact AFM values (initialized with data tables)
/// 2. **Regression**: Uses polynomial formulas with uncertainty estimates (initialized without data tables)
///
/// The regression approach includes RMSE uncertainty from curve fitting, propagated
/// through to the final result.
///
/// ## Usage
///
/// ```swift
/// // For tabular model
/// let calculator = ContaminationCalculator(
///   aircraftType: .g2Plus,
///   loader: dataTableLoader
/// )
///
/// // For regression model
/// let calculator = ContaminationCalculator(aircraftType: .g2Plus)
///
/// let adjustedDistance = calculator.landingRunContaminationAddition(
///   distance: baseDistance,
///   contamination: .wetRunway
/// )
/// ```
final class ContaminationCalculator {

  // MARK: - Constants

  /// The shallowest and deepest contaminant depths, in inches, the AFM's water and slush tables
  /// tabulate, and so the span the regression formulas were fitted over.
  private static let
    shallowestTabulatedDepthInches = Contamination.shallowestTabulatedDepth
      .converted(to: .inches).value,
    deepestTabulatedDepthInches = Contamination.deepestTabulatedDepth
      .converted(to: .inches).value

  /// The deepest contaminant, in inches, the regression formulas are extrapolated to.
  ///
  /// The formulas are extrapolated no further past the tabulated depths than those depths
  /// themselves span — three eighths of an inch — which puts the ceiling at seven eighths of an
  /// inch. Deeper than that the fitted shape rather than the physics sets the answer: both
  /// formulas carry a term in distance times depth that grows without bound, so the water formula
  /// falls through zero near an inch and a half and reaches thousands of feet negative by three.
  ///
  /// Below the ceiling the water formula does put a deep contaminant's ground run under the dry
  /// one, from about two thirds of an inch. That is an answer rather than a failure: deep
  /// contaminant displaces and sprays, and the drag of it decelerates the aircraft. What the
  /// ceiling rules out is the distance the formula has no physics left to justify.
  private static let deepestExtrapolatedDepthInches =
    deepestTabulatedDepthInches + (deepestTabulatedDepthInches - shallowestTabulatedDepthInches)

  /// Wet runway landing distance factor per AFM (15% increase).
  private static let wetRunwayFactor: Double = 1.15

  // MARK: - Properties

  private let aircraftType: AircraftType

  // Data tables for tabular mode (nil for regression mode)
  private let compactSnowData: DataTable?
  private let drySnowData: DataTable?
  private let slushData: DataTable?
  private let waterData: DataTable?

  /// RwyCC landing distance factors (AC 91-79B) keyed by code (1-6)
  private let rwyCCLDFGrooved: [UInt8: Double]
  private let rwyCCLDFSmooth: [UInt8: Double]

  /// Whether this calculator uses tabular data (vs regression formulas)
  private var usesTabularData: Bool { waterData != nil }

  // MARK: - Initializers

  /// Creates a contamination calculator for tabular model (with data tables).
  ///
  /// Use this initializer when the performance model uses tabular interpolation
  /// from digitized AFM data.
  ///
  /// - Parameters:
  ///   - aircraftType: The aircraft type
  ///   - loader: The data table loader to load contamination tables from
  init(aircraftType: AircraftType, loader: DataTableLoader) {
    self.aircraftType = aircraftType
    self.compactSnowData = loader.loadContaminationCompactSnowData()
    self.drySnowData = loader.loadContaminationDrySnowData()
    self.slushData = loader.loadContaminationSlushData()
    self.waterData = loader.loadContaminationWaterData()
    self.rwyCCLDFGrooved = Self.loadRwyCCFactors(filename: "rwycc_ldf_grooved")
    self.rwyCCLDFSmooth = Self.loadRwyCCFactors(filename: "rwycc_ldf_smooth")
  }

  /// Creates a contamination calculator for regression model (no data tables).
  ///
  /// Use this initializer when the performance model uses polynomial regression
  /// formulas derived from AFM data.
  ///
  /// - Parameter aircraftType: The aircraft type
  init(aircraftType: AircraftType) {
    self.aircraftType = aircraftType
    self.compactSnowData = nil
    self.drySnowData = nil
    self.slushData = nil
    self.waterData = nil
    self.rwyCCLDFGrooved = Self.loadRwyCCFactors(filename: "rwycc_ldf_grooved")
    self.rwyCCLDFSmooth = Self.loadRwyCCFactors(filename: "rwycc_ldf_smooth")
  }

  // MARK: - Type Methods

  /// Whether the regression formulas answer for a contaminant of the given depth, in inches.
  ///
  /// Shallower than the tabulated depths the formulas converge on the tables' own shallow-water
  /// worst case — roughly nineteen tenths of the dry ground run for water and seventeen tenths for
  /// slush, since shallow contaminant brakes worse than deep contaminant drags — so extrapolating
  /// down to a film of water stays bounded and conservative. A depth of zero is the one that falls
  /// out below: it describes a clean runway, which is not what a contaminant reading is for.
  /// Deeper, the formulas run out at the extrapolation ceiling.
  private static func isExtrapolable(depthInches: Double) -> Bool {
    depthInches > 0 && depthInches <= deepestExtrapolatedDepthInches
  }

  // MARK: - Public Methods

  /// Calculates the contamination adjustment to landing run distance.
  ///
  /// This method applies the appropriate contamination factor based on the type
  /// and the calculator's configuration (tabular vs regression).
  /// RwyCC contamination does not affect the landing run (it applies to total distance).
  ///
  /// - Parameters:
  ///   - distance: The base landing run distance
  ///   - contamination: The contamination type, or nil for clean runway
  ///   - isGroovedOrPFC: Whether the runway is grooved or has PFC treatment
  /// - Returns: The adjusted landing run distance with contamination effects
  func landingRunContaminationAddition(
    distance: Value<Double>,
    contamination: Contamination?,
    isGroovedOrPFC: Bool
  ) -> Value<Double> {
    guard let contamination else { return distance }

    if case .rwyCC(let rwyCC) = contamination,
      let ldf = rwyCCLandingDistanceFactor(code: rwyCC, isGroovedPFC: isGroovedOrPFC)
    {
      return distance.map { value, unc in (value * ldf, unc.map { $0 * ldf }) }
    }

    if usesTabularData {
      return tabularContamination(distance: distance, contamination: contamination)
    }
    return regressionContamination(distance: distance, contamination: contamination)
  }

  /// Calculates the contaminated landing distance from base landing distance and run.
  ///
  /// This method encapsulates the full contamination adjustment for landing distance,
  /// handling both RwyCC (landing distance factor) and non-RwyCC (run-increase) paths:
  ///
  /// - **RwyCC**: Multiplies the base landing distance by the appropriate LDF.
  /// - **Non-RwyCC contamination**: Computes the contaminated ground run, then adds the
  ///   difference (contaminated run - base run) to the base landing distance. This reflects
  ///   the AFM approach where contamination only affects the ground run, not the air segment.
  /// - **No contamination**: Returns the base landing distance unchanged.
  ///
  /// - Parameters:
  ///   - landingDistance: The base (dry) landing distance
  ///   - landingRun: The base (dry) landing ground run
  ///   - contamination: The contamination type, or nil for clean runway
  ///   - isGroovedOrPFC: Whether the runway is grooved or has PFC treatment
  /// - Returns: The contamination-adjusted landing distance
  func landingDistanceContaminationAddition(
    landingDistance: Value<Double>,
    landingRun: Value<Double>,
    contamination: Contamination?,
    isGroovedOrPFC: Bool
  ) -> Value<Double> {
    guard let contamination else { return landingDistance }

    // RwyCC: multiply total distance by the landing distance factor
    if case .rwyCC(let rwyCC) = contamination,
      let ldf = rwyCCLandingDistanceFactor(code: rwyCC, isGroovedPFC: isGroovedOrPFC)
    {
      return landingDistance * ldf
    }

    // Non-RwyCC: contamination only affects the ground run
    let contaminatedRun = landingRunContaminationAddition(
      distance: landingRun,
      contamination: contamination,
      isGroovedOrPFC: isGroovedOrPFC
    )
    let runIncrease = contaminatedRun - landingRun
    return landingDistance + runIncrease
  }

  /// Returns the RwyCC landing distance factor for the given code and surface type.
  ///
  /// - Parameters:
  ///   - code: Runway Condition Code (1–6)
  ///   - isGroovedPFC: Whether the runway is grooved or has PFC treatment
  /// - Returns: The landing distance factor, or nil if the code is invalid
  func rwyCCLandingDistanceFactor(code: UInt8, isGroovedPFC: Bool) -> Double? {
    precondition((1...6).contains(code), "RwyCC must be 1–6")
    let table = isGroovedPFC ? rwyCCLDFGrooved : rwyCCLDFSmooth
    return table[code]
  }

  // MARK: - Tabular Contamination

  private func tabularContamination(
    distance: Value<Double>,
    contamination: Contamination
  ) -> Value<Double> {
    switch contamination {
      case .wetRunway:
        // G2/G2+ AFM Reissue A: Add 15% to landing ground distance for wet runway
        // G1: No effect (tabular data doesn't include wet runway adjustment)
        guard aircraftType.hasWetRunwayLandingDistanceFactor else { return distance }
        return distance.map { value, uncertainty in
          (value * Self.wetRunwayFactor, uncertainty.map { $0 * Self.wetRunwayFactor })
        }

      case .waterOrSlush(let depth):
        guard let waterData else { return distance }
        return tabularDepthContamination(distance: distance, depth: depth, in: waterData)

      case .slushOrWetSnow(let depth):
        guard let slushData else { return distance }
        return tabularDepthContamination(distance: distance, depth: depth, in: slushData)

      case .drySnow:
        return tabularDrySnowContamination(distance: distance)

      case .compactSnow:
        return tabularCompactSnowContamination(distance: distance)

      case .rwyCC:
        // RwyCC is handled at the performance model level via LDF; should not reach here
        return distance
    }
  }

  // MARK: - Regression Contamination

  private func regressionContamination(
    distance: Value<Double>,
    contamination: Contamination
  ) -> Value<Double> {
    switch contamination {
      case .wetRunway:
        // Regression model: Apply 15% increase for all aircraft types
        return distance.map { value, uncertainty in
          (value * Self.wetRunwayFactor, uncertainty.map { $0 * Self.wetRunwayFactor })
        }

      case .waterOrSlush(let depth):
        return regressionWaterContamination(distance: distance, depth: depth)

      case .slushOrWetSnow(let depth):
        return regressionSlushContamination(distance: distance, depth: depth)

      case .drySnow:
        return regressionDrySnowContamination(distance: distance)

      case .compactSnow:
        return regressionCompactSnowContamination(distance: distance)

      case .rwyCC:
        // RwyCC is handled at the performance model level via LDF; should not reach here
        return distance
    }
  }

  // MARK: - Tabular Contamination Methods

  /// The AFM's contaminated ground run, read from a table tabulated by dry ground run and
  /// contaminant depth.
  ///
  /// The depth axis is left unclamped, so a depth outside the tabulated range comes back offscale.
  /// The tables carry no distance for such a runway, and reading one at the nearest depth they do
  /// carry would present an answer the AFM never gave.
  private func tabularDepthContamination(
    distance: Value<Double>,
    depth: Measurement<UnitLength>,
    in table: DataTable
  ) -> Value<Double> {
    let depthInches = depth.converted(to: .inches).value

    return distance.flatMap { distanceValue in
      table.value(for: [distanceValue, depthInches], clamping: [.clampBoth, .none])
    }
  }

  private func tabularDrySnowContamination(distance: Value<Double>) -> Value<Double> {
    guard let drySnowData else { return distance }

    return distance.flatMap { distanceValue in
      drySnowData.value(for: [distanceValue], clamping: [.clampBoth])
    }
  }

  private func tabularCompactSnowContamination(distance: Value<Double>) -> Value<Double> {
    guard let compactSnowData else { return distance }

    return distance.flatMap { distanceValue in
      compactSnowData.value(for: [distanceValue], clamping: [.clampBoth])
    }
  }

  // MARK: - Regression Contamination Methods

  private func regressionWaterContamination(
    distance: Value<Double>,
    depth: Measurement<UnitLength>
  ) -> Value<Double> {
    let depthInches = depth.converted(to: .inches).value
    guard Self.isExtrapolable(depthInches: depthInches) else { return .notAvailable }

    return distance.map { distanceValue, existingUncertainty in
      // Polynomial regression with interaction term: distance * depth
      // This captures the AFM behavior where shallower water causes more distance increase
      // than deeper water (due to reduced braking vs. increased drag)
      let newDistance =
        1.894551e+00 * distanceValue
        + 1.804096e+00 * depthInches
        - 1.319545e+00 * distanceValue * depthInches
        + 4.370052e+00

      let contaminationUncertainty = ResidualErrorCalculator.contaminationRMSE(
        for: "water",
        distance: distanceValue,
        depth: depthInches
      )

      let newUncertainty =
        if let existingUncertainty {
          sqrt(pow(existingUncertainty, 2) + pow(contaminationUncertainty, 2))
        } else {
          contaminationUncertainty
        }

      return (newDistance, newUncertainty)
    }
  }

  private func regressionSlushContamination(
    distance: Value<Double>,
    depth: Measurement<UnitLength>
  ) -> Value<Double> {
    let depthInches = depth.converted(to: .inches).value
    guard Self.isExtrapolable(depthInches: depthInches) else { return .notAvailable }

    return distance.map { distanceValue, existingUncertainty in
      let newDistance =
        1.692337e+00 * distanceValue
        - 2.335086e-03 * depthInches
        + 3.409392e-07 * pow(distanceValue, 2)
        - 6.240405e-01 * distanceValue * depthInches
        + 1.113034e-01 * pow(depthInches, 2)
        + 7.443967e+00

      let contaminationUncertainty = ResidualErrorCalculator.contaminationRMSE(
        for: "slush, wet snow",
        distance: distanceValue,
        depth: depthInches
      )

      let newUncertainty =
        if let existingUncertainty {
          sqrt(pow(existingUncertainty, 2) + pow(contaminationUncertainty, 2))
        } else {
          contaminationUncertainty
        }

      return (newDistance, newUncertainty)
    }
  }

  private func regressionDrySnowContamination(distance: Value<Double>) -> Value<Double> {
    return distance.map { distanceValue, existingUncertainty in
      let newDistance =
        1.328947e+00 * distanceValue
        + 5.263158e+00

      let contaminationUncertainty = ResidualErrorCalculator.contaminationRMSE(
        for: "dry snow",
        distance: distanceValue
      )

      let newUncertainty =
        if let existingUncertainty {
          sqrt(pow(existingUncertainty, 2) + pow(contaminationUncertainty, 2))
        } else {
          contaminationUncertainty
        }

      return (newDistance, newUncertainty)
    }
  }

  private func regressionCompactSnowContamination(distance: Value<Double>) -> Value<Double> {
    return distance.map { distanceValue, existingUncertainty in
      let newDistance =
        1.578947e+00 * distanceValue
        + 5.263158e+00

      let contaminationUncertainty = ResidualErrorCalculator.contaminationRMSE(
        for: "compact snow",
        distance: distanceValue
      )

      let newUncertainty =
        if let existingUncertainty {
          sqrt(pow(existingUncertainty, 2) + pow(contaminationUncertainty, 2))
        } else {
          contaminationUncertainty
        }

      return (newDistance, newUncertainty)
    }
  }
}

// MARK: - CSV Loading

extension ContaminationCalculator {
  /// Loads RwyCC LDF values from a CSV file in the g1/landing data directory.
  ///
  /// CSV format: `rwycc,value` (header row, then code-value pairs).
  /// AC 91-79B factors are aircraft-independent, so always loaded from g1.
  fileprivate static func loadRwyCCFactors(filename: String) -> [UInt8: Double] {
    guard
      let url = Bundle(for: BasePerformanceModel.self).url(
        forResource: filename,
        withExtension: "csv",
        subdirectory: "Data/g1/landing"
      )
    else {
      assertionFailure("Missing RwyCC CSV file: \(filename)")
      return [:]
    }

    guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
      assertionFailure("Could not read RwyCC CSV file: \(filename)")
      return [:]
    }

    var factors = [UInt8: Double]()
    let lines = contents.components(separatedBy: .newlines)

    for line in lines.dropFirst() {  // skip header
      let components = line.split(separator: ",")
      guard components.count == 2,
        let code = UInt8(components[0]),
        let value = Double(components[1])
      else { continue }
      factors[code] = value
    }

    return factors
  }
}

extension AircraftType {
  var hasWetRunwayLandingDistanceFactor: Bool {
    switch self {
      case .g1: false
      case .g2, .g2Plus: true
    }
  }
}
