import Foundation

/// Altitude-varying climb performance data with interpolation.
///
/// Stores atmospheric and performance data for multiple climb schedules
/// (takeoff, enroute obstacle, enroute) with and without anti-ice, and
/// provides interpolated access by altitude.
public struct ClimbProfile: Sendable {

  /// Sea-level pressure for TAS computation.
  public let seaLevelPressureInHg: Double

  /// Data points sorted by altitude ascending.
  public let dataPoints: [DataPoint]

  public init(dataPoints: [DataPoint], seaLevelPressureInHg: Double) {
    self.dataPoints = dataPoints.sorted { $0.altitudeFt < $1.altitudeFt }
    self.seaLevelPressureInHg = seaLevelPressureInHg
  }

  // MARK: - Interpolation

  /// Interpolates a value at a given altitude using bracketing data points.
  /// Clamps to nearest endpoint outside range. Returns nil if empty.
  private func interpolate(at altitudeFt: Double, _ extract: (DataPoint) -> Double) -> Double? {
    guard let first = dataPoints.first, let last = dataPoints.last else { return nil }
    if altitudeFt <= first.altitudeFt { return extract(first) }
    if altitudeFt >= last.altitudeFt { return extract(last) }

    for i in 0..<(dataPoints.count - 1) {
      let lo = dataPoints[i]
      let hi = dataPoints[i + 1]
      if altitudeFt >= lo.altitudeFt && altitudeFt <= hi.altitudeFt {
        let fraction = (altitudeFt - lo.altitudeFt) / (hi.altitudeFt - lo.altitudeFt)
        return extract(lo) + fraction * (extract(hi) - extract(lo))
      }
    }

    return extract(last)
  }

  /// Interpolated gradient at a given altitude for a specific profile.
  public func gradient(at altitudeFt: Double, profile: ProfileType) -> Double? {
    interpolate(at: altitudeFt) { $0.climbData(for: profile).gradientFtPerNM }
  }

  /// Interpolated true airspeed at a given altitude for a specific profile.
  public func trueAirspeed(at altitudeFt: Double, profile: ProfileType) -> Double? {
    interpolate(at: altitudeFt) {
      $0.trueAirspeedKts(profile: profile, seaLevelPressureInHg: seaLevelPressureInHg)
    }
  }

  /// Interpolated wind direction (true, FROM) at a given altitude.
  public func windDirection(at altitudeFt: Double) -> Double? {
    interpolate(at: altitudeFt) { $0.windDirectionDeg }
  }

  /// Interpolated wind speed at a given altitude.
  public func windSpeed(at altitudeFt: Double) -> Double? {
    interpolate(at: altitudeFt) { $0.windSpeedKts }
  }

  // MARK: - Integration

  /// Aircraft altitude after climbing a horizontal distance from a starting altitude.
  /// Uses trapezoidal integration over the gradient curve.
  /// Returns nil if the profile is empty or distance is negative.
  public func altitude(after distanceNM: Double, from startAltitudeFt: Double, profile: ProfileType)
    -> Double?
  {
    guard distanceNM >= 0, !dataPoints.isEmpty else { return nil }
    guard distanceNM > 0 else { return startAltitudeFt }

    let stepNM = 0.1
    var remainingNM = distanceNM
    var currentAltitudeFt = startAltitudeFt

    while remainingNM > 0 {
      let step = min(stepNM, remainingNM)
      guard let g1 = gradient(at: currentAltitudeFt, profile: profile) else {
        fatalError("Non-empty profile returned nil gradient")
      }
      let predictedAltitudeFt = currentAltitudeFt + g1 * step
      guard let g2 = gradient(at: predictedAltitudeFt, profile: profile) else {
        fatalError("Non-empty profile returned nil gradient")
      }
      currentAltitudeFt += (g1 + g2) / 2.0 * step
      remainingNM -= step
    }

    return currentAltitudeFt
  }

  /// Horizontal distance required to climb from one altitude to another.
  /// Uses trapezoidal integration over the gradient curve.
  /// Returns nil if the profile is empty or startAltitudeFt >= endAltitudeFt.
  public func distance(from startAltitudeFt: Double, to endAltitudeFt: Double, profile: ProfileType)
    -> Double?
  {
    guard endAltitudeFt > startAltitudeFt, !dataPoints.isEmpty else { return nil }

    let stepFt = 50.0
    var remainingFt = endAltitudeFt - startAltitudeFt
    var currentAltitudeFt = startAltitudeFt
    var totalNM = 0.0

    while remainingFt > 0 {
      let step = min(stepFt, remainingFt)
      guard let g1 = gradient(at: currentAltitudeFt, profile: profile) else {
        fatalError("Non-empty profile returned nil gradient")
      }
      guard let g2 = gradient(at: currentAltitudeFt + step, profile: profile) else {
        fatalError("Non-empty profile returned nil gradient")
      }
      let avgGradient = (g1 + g2) / 2.0
      if avgGradient > 0 {
        totalNM += step / avgGradient
      }
      currentAltitudeFt += step
      remainingFt -= step
    }

    return totalNM
  }

  // MARK: - Profile Type

  /// Identifies which climb profile + anti-ice state to use.
  public struct ProfileType: Sendable, Hashable {

    /// Takeoff climb at Vx. No anti-ice variant (data is invariant).
    public static var takeoff: Self {
      Self(schedule: .takeoff, antiIce: false)
    }

    fileprivate let schedule: ClimbSchedule
    fileprivate let antiIce: Bool

    public static func enrouteObstacle(antiIce: Bool) -> Self {
      Self(schedule: .enrouteObstacle, antiIce: antiIce)
    }

    public static func enroute(antiIce: Bool) -> Self {
      Self(schedule: .enroute, antiIce: antiIce)
    }

    fileprivate enum ClimbSchedule: Sendable, Hashable {
      case takeoff, enrouteObstacle, enroute
    }
  }

  // MARK: - Climb Data

  /// Gradient and IAS for a single climb schedule at a single altitude.
  public struct ClimbData: Sendable {
    public let gradientFtPerNM: Double
    public let indicatedAirspeedKts: Double

    public init(gradientFtPerNM: Double, indicatedAirspeedKts: Double) {
      self.gradientFtPerNM = gradientFtPerNM
      self.indicatedAirspeedKts = indicatedAirspeedKts
    }
  }

  // MARK: - Data Point

  /// Per-altitude atmospheric and performance data for all climb profiles.
  public struct DataPoint: Sendable {
    public let altitudeFt: Double
    public let outsideAirTemperatureC: Double
    public let windDirectionDeg: Double  // true north, FROM direction
    public let windSpeedKts: Double

    private let takeoff: ClimbData
    private let enrouteObstacle: ClimbData
    private let enrouteObstacleAntiIce: ClimbData
    private let enroute: ClimbData
    private let enrouteAntiIce: ClimbData

    public init(
      altitudeFt: Double,
      outsideAirTemperatureC: Double,
      windDirectionDeg: Double,
      windSpeedKts: Double,
      takeoff: ClimbData,
      enrouteObstacle: ClimbData,
      enrouteObstacleAntiIce: ClimbData,
      enroute: ClimbData,
      enrouteAntiIce: ClimbData
    ) {
      self.altitudeFt = altitudeFt
      self.outsideAirTemperatureC = outsideAirTemperatureC
      self.windDirectionDeg = windDirectionDeg
      self.windSpeedKts = windSpeedKts
      self.takeoff = takeoff
      self.enrouteObstacle = enrouteObstacle
      self.enrouteObstacleAntiIce = enrouteObstacleAntiIce
      self.enroute = enroute
      self.enrouteAntiIce = enrouteAntiIce
    }

    /// Access climb data for a specific profile type.
    public func climbData(for profile: ProfileType) -> ClimbData {
      switch (profile.schedule, profile.antiIce) {
        case (.takeoff, _): takeoff
        case (.enrouteObstacle, false): enrouteObstacle
        case (.enrouteObstacle, true): enrouteObstacleAntiIce
        case (.enroute, false): enroute
        case (.enroute, true): enrouteAntiIce
      }
    }

    /// Computes TAS from IAS for a given profile using actual density at this altitude.
    func trueAirspeedKts(profile: ProfileType, seaLevelPressureInHg: Double) -> Double {
      let P = pressureAtAltitude(
        seaLevelPressurePa: seaLevelPressureInHg * inHgToPa,
        altitudeM: altitudeFt * feetToMeters
      )
      return SF50_Shared.trueAirspeed(
        indicatedAirspeedKts: climbData(for: profile).indicatedAirspeedKts,
        pressurePa: P,
        temperatureC: outsideAirTemperatureC
      )
    }
  }
}
