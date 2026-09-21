import Foundation

/// Altitude-varying climb performance data with interpolation.
///
/// Stores atmospheric and performance data for multiple climb schedules
/// (takeoff, enroute obstacle, enroute) with and without anti-ice, and
/// provides interpolated access by altitude.
public struct ClimbProfile: Sendable {

  /// Step size in nautical miles for distance-based integration.
  private static let distanceStepNM = 0.1

  /// Step size in feet for altitude-based integration.
  private static let altitudeStepFt = 50.0

  /// Sea-level pressure for TAS computation.
  public let seaLevelPressureInHg: Double

  /// Data points sorted by altitude ascending.
  public let dataPoints: [DataPoint]

  public init(dataPoints: [DataPoint], seaLevelPressureInHg: Double) {
    self.dataPoints = dataPoints.sorted { $0.altitudeFt < $1.altitudeFt }
    self.seaLevelPressureInHg = seaLevelPressureInHg
  }

  // MARK: - Interpolation

  /// Locates an altitude among the profile's data points, clamping to an endpoint outside the
  /// range they cover.
  private func position(at altitudeFt: Double) -> Position? {
    guard let first = dataPoints.first, let last = dataPoints.last else { return nil }
    if altitudeFt <= first.altitudeFt { return .at(first) }
    if altitudeFt >= last.altitudeFt { return .at(last) }

    for (low, high) in zip(dataPoints, dataPoints.dropFirst())
    where altitudeFt >= low.altitudeFt && altitudeFt <= high.altitudeFt {
      // Two observations at one altitude leave nothing to interpolate across, and a span of zero
      // would divide by it.
      guard high.altitudeFt > low.altitudeFt else { return .at(low) }
      let fraction = (altitudeFt - low.altitudeFt) / (high.altitudeFt - low.altitudeFt)
      return .between(low, high, fraction: fraction)
    }

    return .at(last)
  }

  /// Interpolates a quantity every data point carries, such as a wind component.
  private func interpolate(at altitudeFt: Double, _ extract: (DataPoint) -> Double) -> Double? {
    switch position(at: altitudeFt) {
      case nil: nil
      case .at(let point): extract(point)
      case .between(let low, let high, let fraction):
        extract(low) + fraction * (extract(high) - extract(low))
    }
  }

  /// Interpolates a performance figure, which the model may have no answer for at either end of
  /// the bracketing interval.
  ///
  /// Where a bracketing point carries a refusal, that refusal is the answer for the whole
  /// interval, and it is passed out intact rather than reduced to "no figure": a profile that
  /// cannot say what the gradient is at 20,000 ft cannot say what it is at 19,500 ft either, and
  /// interpolating towards the missing point would invent one.
  private func interpolateFigure(
    at altitudeFt: Double,
    _ extract: (DataPoint) -> Value<Double>
  ) -> Value<Double> {
    switch position(at: altitudeFt) {
      case nil: .notAvailable
      case .at(let point): extract(point)
      case .between(let low, let high, let fraction):
        between(extract(low), extract(high), fraction: fraction)
    }
  }

  /// Reads between two figures, or hands back whichever of them the model could not supply.
  private func between(_ low: Value<Double>, _ high: Value<Double>, fraction: Double)
    -> Value<Double>
  {
    guard let lowFigure = low.nominal else { return low }
    guard let highFigure = high.nominal else { return high }
    return .value(lowFigure + fraction * (highFigure - lowFigure))
  }

  /// Interpolated gradient at a given altitude for a specific profile.
  ///
  /// Returns nil where the profile is empty, or where the performance model had no figure at a
  /// bracketing altitude — conditions outside the charts, or a hole in them.
  public func gradient(at altitudeFt: Double, profile: ProfileType) -> Double? {
    interpolateFigure(at: altitudeFt) { $0.climbData(for: profile).gradientFtPerNM }.nominal
  }

  /// Interpolated true airspeed at a given altitude for a specific profile.
  ///
  /// Returns nil on the same terms as ``gradient(at:profile:)``.
  public func trueAirspeed(at altitudeFt: Double, profile: ProfileType) -> Double? {
    interpolateFigure(at: altitudeFt) {
      $0.trueAirspeedKts(profile: profile, seaLevelPressureInHg: seaLevelPressureInHg)
    }.nominal
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
  ///
  /// Uses trapezoidal integration over the gradient curve. Returns nil if the profile is empty,
  /// the distance is negative, or the profile has no gradient at an altitude the climb passes
  /// through — the conditions there are outside the charts, and there is no figure to integrate.
  public func altitude(after distanceNM: Double, from startAltitudeFt: Double, profile: ProfileType)
    -> Double?
  {
    guard distanceNM >= 0, !dataPoints.isEmpty else { return nil }
    guard distanceNM > 0 else { return startAltitudeFt }

    var remainingNM = distanceNM,
      currentAltitudeFt = startAltitudeFt

    while remainingNM > 0 {
      let step = min(Self.distanceStepNM, remainingNM)
      guard let g1 = gradient(at: currentAltitudeFt, profile: profile) else { return nil }
      let predictedAltitudeFt = currentAltitudeFt + g1 * step
      guard let g2 = gradient(at: predictedAltitudeFt, profile: profile) else { return nil }
      currentAltitudeFt += (g1 + g2) / 2.0 * step
      remainingNM -= step
    }

    return currentAltitudeFt
  }

  /// Horizontal distance required to climb from one altitude to another.
  ///
  /// Uses trapezoidal integration over the gradient curve. Returns nil if the profile is empty,
  /// `startAltitudeFt` is not below `endAltitudeFt`, or the profile has no gradient somewhere
  /// between the two.
  public func distance(from startAltitudeFt: Double, to endAltitudeFt: Double, profile: ProfileType)
    -> Double?
  {
    guard endAltitudeFt > startAltitudeFt, !dataPoints.isEmpty else { return nil }

    var remainingFt = endAltitudeFt - startAltitudeFt,
      currentAltitudeFt = startAltitudeFt,
      totalNM = 0.0

    while remainingFt > 0 {
      let step = min(Self.altitudeStepFt, remainingFt)
      guard let g1 = gradient(at: currentAltitudeFt, profile: profile),
        let g2 = gradient(at: currentAltitudeFt + step, profile: profile)
      else { return nil }
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

    /**
     * Whether the AFM publishes no table for this schedule, so it is answered from the fitted
     * equations however the model is set.
     *
     * Only the obstacle climb is served this way. Anything plotting it while the tabular model is
     * selected is showing regression figures, and says so rather than presenting them as the
     * book's.
     */
    public var answeredFromRegressionOnly: Bool {
      schedule == .enrouteObstacle
    }

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
  ///
  /// Both are `Value`s because the model is entitled to have no answer: the conditions at this
  /// altitude may sit outside the charts, or the charts may have a hole where they should be.
  /// Which of those it was survives to whoever reads the figure.
  public struct ClimbData: Sendable {
    public let gradientFtPerNM: Value<Double>
    public let indicatedAirspeedKts: Value<Double>

    public init(gradientFtPerNM: Value<Double>, indicatedAirspeedKts: Value<Double>) {
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
    ///
    /// Where the model had no indicated airspeed to convert, its refusal is the answer.
    func trueAirspeedKts(profile: ProfileType, seaLevelPressureInHg: Double) -> Value<Double> {
      let indicated = climbData(for: profile).indicatedAirspeedKts
      guard let IASKts = indicated.nominal else { return indicated }

      let P = pressureAtAltitude(
        seaLevelPressurePa: seaLevelPressureInHg * inHgToPa,
        altitudeM: altitudeFt * feetToMeters
      )
      return .value(
        SF50_Shared.trueAirspeed(
          indicatedAirspeedKts: IASKts,
          pressurePa: P,
          temperatureC: outsideAirTemperatureC
        )
      )
    }
  }

  // MARK: - Position

  /// Where an altitude falls among the profile's data points.
  private enum Position {
    /// At a single data point: an exact altitude, or one clamped to an endpoint.
    case at(DataPoint)

    /// Between two data points, `fraction` of the way from the first to the second.
    case between(DataPoint, DataPoint, fraction: Double)
  }
}
