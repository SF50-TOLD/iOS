public import Foundation

/// The atmosphere along a flight path, sampled in vertical columns.
///
/// A single forecast column describes the air for some way around it, so most paths need only one.
/// A path that runs further than that samples again, and the layers drawn from it read across the
/// columns — vertically within each, then horizontally between them.
///
/// ## Usage
///
/// ```swift
/// let atmosphere = try await PathAtmosphereLoader.shared.atmosphere(along: points, at: time)
/// let level = atmosphere.level(atDistanceNM: 4.2, altitude: .init(value: 5000, unit: .feet))
/// ```
public struct PathAtmosphere: Sendable {

  /// How far apart two altitudes can stand and still be read as the same reported level.
  ///
  /// The requested pressure levels are never closer together than about seven hundred feet, and one
  /// level's height varies across a path by far less than that, so a band this wide gathers the
  /// restatements of a single level without ever gathering two.
  private static let altitudeBand = Measurement(value: 300, unit: UnitLength.feet)

  /// The columns sampled along the path, ordered by distance from its origin.
  public let columns: [Column]

  /// The services the columns were drawn from, for the credits their licences ask for.
  public let providers: WeatherProviders

  /// Whether the path ran further than the columns cover.
  ///
  /// True when the column limit stopped sampling before the end of the path, so the layers thin out
  /// past the last column rather than describing it.
  public let isTruncated: Bool

  /// Whether any column reported anything.
  public var isEmpty: Bool { columns.isEmpty }

  /// The altitudes the reported levels stand at, across every column, lowest first.
  ///
  /// The grid a vertical scan walks — dense enough to bracket a crossing wherever any column
  /// reports one. Also what a layer with no depth of its own is drawn at: cloud is reported for a
  /// level, not for a band, so a deck belongs on one of these altitudes rather than smeared over
  /// the gap to the next.
  ///
  /// One entry per reported level rather than one per column. A level's altitude is the
  /// geopotential height of a pressure surface, which stands a little differently over each grid
  /// point, so one level arrives as a scatter of nearby altitudes. Gathered into bands and reported
  /// at their mean, so a deck is drawn once instead of as a stack of near-coincident bars whose dash
  /// offsets fill in each other's gaps.
  public let reportedAltitudes: [Measurement<UnitLength>]

  /// Creates an atmosphere from columns sampled along a path.
  ///
  /// - Parameters:
  ///   - columns: The sampled columns, in any order.
  ///   - providers: The services the columns came from.
  ///   - isTruncated: Whether the column limit cut sampling short.
  public init(columns: [Column], providers: WeatherProviders, isTruncated: Bool = false) {
    self.columns = columns.sorted { $0.distanceNM < $1.distanceNM }
    self.providers = providers
    self.isTruncated = isTruncated
    reportedAltitudes = Self.bandedAltitudes(of: columns)
  }

  /// Gathers every column's reported altitudes into one altitude per level, lowest first.
  ///
  /// A band runs from its lowest member to at most ``altitudeBand`` above it, so no band is wider
  /// than one level's spread however many columns fall in it.
  private static func bandedAltitudes(of columns: [Column]) -> [Measurement<UnitLength>] {
    let altitudes = columns.flatMap { $0.profile.levels.map(\.altitude) }.sorted()

    var bands = [(sum: Measurement<UnitLength>, count: Int, lowest: Measurement<UnitLength>)]()
    for altitude in altitudes {
      if let last = bands.last, altitude - last.lowest <= altitudeBand {
        bands[bands.count - 1] = (last.sum + altitude, last.count + 1, last.lowest)
      } else {
        bands.append((altitude, 1, altitude))
      }
    }
    return bands.map { $0.sum / Double($0.count) }
  }

  /// The conditions at a point on the path, read across the columns bracketing it.
  ///
  /// Distances outside the sampled range take the nearest column, for the same reason
  /// ``AtmosphericProfile/level(at:)`` clamps in altitude.
  ///
  /// - Parameters:
  ///   - distanceNM: Distance along the path from its origin, in nautical miles.
  ///   - altitude: The altitude to read.
  /// - Returns: The conditions there, or `nil` if no column reported anything.
  public func level(
    atDistanceNM distanceNM: Double,
    altitude: Measurement<UnitLength>
  ) -> AtmosphericProfile.Level? {
    guard let first = columns.first, let last = columns.last else { return nil }
    if distanceNM <= first.distanceNM { return first.profile.level(at: altitude) }
    if distanceNM >= last.distanceNM { return last.profile.level(at: altitude) }

    guard let afterIndex = columns.firstIndex(where: { $0.distanceNM >= distanceNM }),
      afterIndex > 0
    else { return first.profile.level(at: altitude) }

    let before = columns[afterIndex - 1],
      after = columns[afterIndex]
    guard let lower = before.profile.level(at: altitude),
      let upper = after.profile.level(at: altitude)
    else { return before.profile.level(at: altitude) ?? after.profile.level(at: altitude) }

    let span = after.distanceNM - before.distanceNM
    guard span > 0 else { return lower }

    return .interpolate(
      from: lower,
      to: upper,
      fraction: (distanceNM - before.distanceNM) / span,
      altitude: altitude
    )
  }

  /// Where the temperature crosses freezing above a point on the path.
  ///
  /// Derived from the same levels the temperature layer is drawn from rather than requested as its
  /// own variable, so the isotherm and the field it sits on can never disagree. Read at an arbitrary
  /// distance rather than only at the columns, so a path covered by one column still gets a line
  /// across the chart instead of a single point.
  ///
  /// The lowest crossing is the one reported: it is where a climb enters the cold, and where an
  /// icing band starts.
  ///
  /// - Parameter distanceNM: Distance along the path from its origin, in nautical miles.
  /// - Returns: The freezing level, or `nil` where the column is below freezing throughout or never
  ///   reaches it.
  public func freezingAltitude(atDistanceNM distanceNM: Double) -> Measurement<UnitLength>? {
    let readings = reportedAltitudes.compactMap {
      altitude -> (altitude: Measurement<UnitLength>, celsius: Double)? in
      guard
        let celsius = level(atDistanceNM: distanceNM, altitude: altitude)?
          .temperature?.converted(to: .celsius).value
      else { return nil }
      return (altitude, celsius)
    }

    guard let lowest = readings.first, lowest.celsius > 0 else { return nil }

    for (lower, upper) in zip(readings, readings.dropFirst())
    where lower.celsius > 0 && upper.celsius <= 0 {
      let fraction = lower.celsius / (lower.celsius - upper.celsius)
      return lower.altitude + (upper.altitude - lower.altitude) * fraction
    }
    return nil
  }

  /// The freezing level across a path, sampled finely enough to draw as a curve.
  ///
  /// Sampled at its own distances rather than at the columns: a path covered by a single column
  /// still wants a line drawn all the way across, not one point. Points outside the altitude band
  /// are dropped, so an empty result means there is no freezing level to draw — and no legend to
  /// key it with.
  ///
  /// - Parameters:
  ///   - maxDistanceNM: The far end of the path, in nautical miles.
  ///   - lower: The bottom of the visible band.
  ///   - upper: The top of the visible band.
  ///   - samples: How many distances across the path to read.
  /// - Returns: The freezing level where it falls inside the band.
  public func freezingLevel(
    toDistanceNM maxDistanceNM: Double,
    between lower: Measurement<UnitLength>,
    and upper: Measurement<UnitLength>,
    samples: Int = 40
  ) -> [(distanceNM: Double, altitude: Measurement<UnitLength>)] {
    guard !isEmpty, maxDistanceNM > 0, samples > 0 else { return [] }

    let step = maxDistanceNM / Double(samples)
    return (0...samples).compactMap { sample in
      let distanceNM = step * Double(sample)
      guard let altitude = freezingAltitude(atDistanceNM: distanceNM),
        altitude > lower,
        altitude < upper
      else { return nil }
      return (distanceNM, altitude)
    }
  }

  /// The temperatures reported across a band of altitude, for a legend to key a field against.
  ///
  /// - Parameters:
  ///   - lower: The bottom of the band.
  ///   - upper: The top of the band.
  ///   - samples: How many altitudes across the band to read.
  /// - Returns: The span of reported temperatures, or `nil` if the band reports none, or all the
  ///   same one.
  public func temperatureRange(
    from lower: Measurement<UnitLength>,
    to upper: Measurement<UnitLength>,
    samples: Int = 12
  ) -> ClosedRange<Measurement<UnitTemperature>>? {
    guard upper > lower, samples > 1 else { return nil }

    let step = (upper - lower) / Double(samples - 1)
    let temperatures = (0..<samples).flatMap { sample -> [Measurement<UnitTemperature>] in
      let altitude = lower + step * Double(sample)
      return columns.compactMap { $0.profile.level(at: altitude)?.temperature }
    }

    guard let lowest = temperatures.min(), let highest = temperatures.max(), highest > lowest else {
      return nil
    }
    return lowest...highest
  }

  /// One column of the atmosphere, and where along the path it stands.
  public struct Column: Sendable {

    /// Distance from the path's origin to this column, in nautical miles.
    public let distanceNM: Double

    /// The atmosphere above this point.
    public let profile: AtmosphericProfile

    /// Creates a column at a distance along a path.
    ///
    /// - Parameters:
    ///   - distanceNM: Distance from the path's origin, in nautical miles.
    ///   - profile: The atmosphere above this point.
    public init(distanceNM: Double, profile: AtmosphericProfile) {
      self.distanceNM = distanceNM
      self.profile = profile
    }
  }
}
