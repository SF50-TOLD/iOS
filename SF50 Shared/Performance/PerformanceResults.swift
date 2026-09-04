public import Foundation
public import MeasurementKit

/// Results of a takeoff performance calculation.
public struct TakeoffResults: Sendable {
  /// Ground run distance from brake release to liftoff.
  public let takeoffRun: Value<Measurement<UnitLength>>

  /// Total distance from brake release to 35 feet AGL.
  public let takeoffDistance: Value<Measurement<UnitLength>>

  /// Climb gradient in feet per nautical mile at Vx.
  public let takeoffClimbGradient: Value<Measurement<UnitSlope>>

  /// Climb rate in feet per minute at Vx.
  public let takeoffClimbRate: Value<Measurement<UnitSpeed>>
}

/// Results of a landing performance calculation.
public struct LandingResults: Sendable {
  /// Reference approach speed for the landing configuration.
  public let Vref: Value<Measurement<UnitSpeed>>

  /// Ground run distance from touchdown to stop.
  public let landingRun: Value<Measurement<UnitLength>>

  /// Total distance from 50 feet AGL to full stop.
  public let landingDistance: Value<Measurement<UnitLength>>

  /// Whether the aircraft can achieve the required go-around climb gradient.
  public let meetsGoAroundClimbGradient: Value<Bool>
}

/// A takeoff report including results and distance breakdowns.
public struct TakeoffReport: Sendable {
  public let results: TakeoffResults
  public let groundRunBreakdown: DistanceBreakdown
  public let distanceBreakdown: DistanceBreakdown
}

/// A landing report including results and distance breakdowns.
public struct LandingReport: Sendable {
  public let results: LandingResults
  public let groundRunBreakdown: DistanceBreakdown
  public let distanceBreakdown: DistanceBreakdown
}
