public import Foundation
public import MeasurementKit

/// The performance numbers for one runway on one leg.
///
/// Which fields are populated depends on the leg: a takeoff has a Vx climb gradient and no reference
/// speed, a landing the reverse. Every number keeps its ``Value`` wrapper so a refusal — off the end of
/// the AFM tables, or a configuration that is not authorized — survives to the readout instead of being
/// flattened into a plausible-looking number.
public struct RunwayPerformance: Sendable {
  /// Ground run: brake release to liftoff, or touchdown to full stop.
  public let groundRun: Value<Measurement<UnitLength>>

  /// Total distance: over the 35 ft screen on takeoff, from the 50 ft screen on landing.
  public let distance: Value<Measurement<UnitLength>>

  /// Climb gradient at Vx. Takeoff only.
  public let climbGradient: Value<Measurement<UnitSlope>>?

  /// Reference approach speed. Landing only.
  public let VREF: Value<Measurement<UnitSpeed>>?

  /// Creates a result from already-calculated values.
  ///
  /// - Parameters:
  ///   - groundRun: Ground run distance.
  ///   - distance: Total distance over or from the screen height.
  ///   - climbGradient: Vx climb gradient, for a takeoff.
  ///   - VREF: Reference approach speed, for a landing.
  public init(
    groundRun: Value<Measurement<UnitLength>>,
    distance: Value<Measurement<UnitLength>>,
    climbGradient: Value<Measurement<UnitSlope>>? = nil,
    VREF: Value<Measurement<UnitSpeed>>? = nil
  ) {
    self.groundRun = groundRun
    self.distance = distance
    self.climbGradient = climbGradient
    self.VREF = VREF
  }

  /// Creates a takeoff result.
  ///
  /// - Parameter results: The calculated takeoff results.
  public init(takeoff results: TakeoffResults) {
    groundRun = results.takeoffRun
    distance = results.takeoffDistance
    climbGradient = results.takeoffClimbGradient
    VREF = nil
  }

  /// Creates a landing result.
  ///
  /// - Parameter results: The calculated landing results.
  public init(landing results: LandingResults) {
    groundRun = results.landingRun
    distance = results.landingDistance
    climbGradient = nil
    VREF = results.Vref
  }

  /// Creates a result standing in for a calculation that threw.
  ///
  /// - Parameter operation: The leg that was being calculated, which decides which fields exist.
  public init(invalidFor operation: Operation) {
    groundRun = .invalid
    distance = .invalid
    climbGradient = operation == .takeoff ? .invalid : nil
    VREF = operation == .landing ? .invalid : nil
  }
}

/// Everything a headless readout needs about one airport at one moment.
///
/// The widget timeline and the App Intents surfaces both consume this, so neither has to reach into
/// SwiftData or the weather loader itself.
public struct AirportPerformance: Sendable {
  /// The airport's `recordID`.
  public let airportRecordID: String

  /// The airport's name.
  public let airportName: String

  /// The identifier the app shows for the airport.
  public let airportDisplayID: String

  /// The leg these numbers were calculated for.
  public let operation: Operation

  /// Every runway at the airport.
  public let runways: [RunwaySnapshot]

  /// The conditions the numbers were calculated from, or `nil` when weather could not be loaded.
  public let conditions: Conditions?

  /// Results keyed by runway name. Empty when there were no conditions to calculate from.
  public let results: [String: RunwayPerformance]

  /// Creates a result set.
  ///
  /// - Parameters:
  ///   - airportRecordID: The airport's `recordID`.
  ///   - airportName: The airport's name.
  ///   - airportDisplayID: The identifier the app shows for the airport.
  ///   - operation: The leg calculated.
  ///   - runways: Every runway at the airport.
  ///   - conditions: The conditions used, or `nil` if weather could not be loaded.
  ///   - results: Results keyed by runway name.
  public init(
    airportRecordID: String,
    airportName: String,
    airportDisplayID: String,
    operation: Operation,
    runways: [RunwaySnapshot],
    conditions: Conditions?,
    results: [String: RunwayPerformance]
  ) {
    self.airportRecordID = airportRecordID
    self.airportName = airportName
    self.airportDisplayID = airportDisplayID
    self.operation = operation
    self.runways = runways
    self.conditions = conditions
    self.results = results
  }

  /// The runway with the given name, if the airport has one.
  ///
  /// - Parameter name: The runway designator.
  /// - Returns: The runway snapshot, or `nil` if the airport has no such runway.
  public func runway(named name: String) -> RunwaySnapshot? {
    runways.first { $0.name == name }
  }
}
