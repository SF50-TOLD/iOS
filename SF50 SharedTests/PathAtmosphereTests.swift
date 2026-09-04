import CoreLocation
import Foundation
import RealModule
import Testing

@testable import SF50_Shared

/// Builds paths and columns for the tests below.
private enum Fixture {

  static let origin = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)

  /// A path running due north from ``origin``, sampled every tenth of a mile.
  ///
  /// Matches the tenth-of-a-mile integration step ``ProcedurePathGenerator`` walks paths with.
  static func path(lengthNM: Double) -> [PathAtmosphereLoader.PathPoint] {
    let stepNM = 0.1
    return stride(from: 0, through: lengthNM, by: stepNM).map { distanceNM in
      .init(
        coordinate: GeoCalculations.destination(
          from: origin,
          distance: .init(value: distanceNM, unit: .nauticalMiles),
          bearing: .init(value: 0, unit: .degrees)
        ),
        distanceNM: distanceNM
      )
    }
  }

  /// A column whose temperature falls from `surfaceC` at sea level at a fixed rate.
  ///
  /// - Parameter altitudeOffsetFt: How far this column's levels stand from their nominal altitudes,
  ///   standing in for the geopotential height of one pressure surface differing between grid
  ///   points.
  static func column(
    distanceNM: Double,
    surfaceC: Double,
    lapseRateCPer1000Ft: Double = 2,
    cloudCover: Double? = nil,
    relativeHumidity: Double? = nil,
    altitudeOffsetFt: Double = 0
  ) -> PathAtmosphere.Column {
    let levels = stride(from: 0.0, through: 12000.0, by: 3000.0).map { altitudeFt in
      AtmosphericProfile.Level(
        altitude: .init(value: altitudeFt + altitudeOffsetFt, unit: .feet),
        temperature: .init(
          value: surfaceC - lapseRateCPer1000Ft * altitudeFt / 1000,
          unit: .celsius
        ),
        relativeHumidity: relativeHumidity,
        cloudCover: cloudCover
      )
    }
    return .init(
      distanceNM: distanceNM,
      profile: .init(
        coordinate: origin,
        validTime: .init(start: .init(timeIntervalSince1970: 0), duration: 3600),
        levels: levels
      )
    )
  }
}

struct PathAtmosphereColumnSelectionTests {

  @Test
  func `samples once for a path that never leaves the first column’s reach`() {
    let (indices, truncated) = PathAtmosphereLoader.columnIndices(
      along: Fixture.path(lengthNM: 4.5)
    )

    #expect(indices == [0])
    #expect(!truncated)
  }

  @Test
  func `samples again only once the path has left every column behind`() {
    let (indices, truncated) = PathAtmosphereLoader.columnIndices(
      along: Fixture.path(lengthNM: 22)
    )

    #expect(!truncated)
    // 22 NM at a five-mile reach: the origin, then one just past each subsequent five miles.
    #expect(indices.count == 5)
    #expect(indices.first == 0)
  }

  @Test
  func `spaces the columns by about the radius they describe`() {
    let points = Fixture.path(lengthNM: 30)
    let (indices, _) = PathAtmosphereLoader.columnIndices(along: points)
    let distances = indices.map { points[$0].distanceNM }

    for (earlier, later) in zip(distances, distances.dropFirst()) {
      let gap = later - earlier
      // Each column is taken at the first point past the previous one's reach — never inside it,
      // and never much beyond it.
      #expect(gap >= PathAtmosphereLoader.columnRadiusNM)
      #expect(gap < PathAtmosphereLoader.columnRadiusNM + 0.5)
    }
  }

  @Test
  func `stops at the column limit and says the path outran it`() {
    let lengthNM =
      Double(PathAtmosphereLoader.maxColumns + 5) * PathAtmosphereLoader.columnRadiusNM
    let (indices, truncated) = PathAtmosphereLoader.columnIndices(
      along: Fixture.path(lengthNM: lengthNM)
    )

    #expect(indices.count == PathAtmosphereLoader.maxColumns)
    #expect(truncated)
  }

  @Test
  func `has nothing to sample on an empty path`() {
    let (indices, truncated) = PathAtmosphereLoader.columnIndices(along: [])

    #expect(indices.isEmpty)
    #expect(!truncated)
  }
}

struct PathAtmosphereFailureTests {

  @Test(arguments: [
    URLError.Code.notConnectedToInternet,
    .networkConnectionLost,
    .timedOut,
    .dnsLookupFailed,
    .cannotConnectToHost,
    .dataNotAllowed
  ])
  func `reads anything that means the service was unreachable as being offline`(code: URLError.Code)
  {
    #expect(PathAtmosphereLoader.Failure(URLError(code)) == .offline)
  }

  @Test
  func `reads a service that answered badly as unavailable rather than offline`() {
    let url = URL(string: "https://example.com")!

    #expect(
      PathAtmosphereLoader.Failure(WeatherLoader.Errors.serviceError(url: url, reason: "nope"))
        == .unavailable
    )
    #expect(PathAtmosphereLoader.Failure(URLError(.badServerResponse)) == .unavailable)
  }

  @Test
  func `keeps a verdict it has already reached`() {
    #expect(PathAtmosphereLoader.Failure(PathAtmosphereLoader.Failure.offline) == .offline)
  }
}

struct PathAtmosphereSamplingTests {

  private let atmosphere = PathAtmosphere(
    columns: [
      Fixture.column(distanceNM: 0, surfaceC: 20),
      Fixture.column(distanceNM: 10, surfaceC: 10)
    ],
    providers: .openMeteo
  )

  @Test
  func `reads between the columns bracketing a distance`() throws {
    let level = try #require(
      atmosphere.level(atDistanceNM: 5, altitude: .init(value: 0, unit: .feet))
    )

    #expect(
      try #require(level.temperature).converted(to: .celsius).value
        .isApproximatelyEqual(to: 15, absoluteTolerance: 0.01)
    )
  }

  @Test
  func `reads across distance and altitude together`() throws {
    // Halfway along, 3,000 ft up: 15 °C at the surface less two degrees a thousand feet.
    let level = try #require(
      atmosphere.level(atDistanceNM: 5, altitude: .init(value: 3000, unit: .feet))
    )

    #expect(
      try #require(level.temperature).converted(to: .celsius).value
        .isApproximatelyEqual(to: 9, absoluteTolerance: 0.01)
    )
  }

  @Test
  func `carries the end columns beyond the distance they were sampled over`() throws {
    let before = try #require(
      atmosphere.level(atDistanceNM: -3, altitude: .init(value: 0, unit: .feet))
    )
    let after = try #require(
      atmosphere.level(atDistanceNM: 40, altitude: .init(value: 0, unit: .feet))
    )

    #expect(
      try #require(before.temperature).converted(to: .celsius).value
        .isApproximatelyEqual(to: 20, absoluteTolerance: 0.01)
    )
    #expect(
      try #require(after.temperature).converted(to: .celsius).value
        .isApproximatelyEqual(to: 10, absoluteTolerance: 0.01)
    )
  }

  /// A deck is drawn once per reported altitude, so a level arriving as one altitude per column
  /// would stack a bar per column at nearly the same height, and their offset dashes would fill in
  /// each other's gaps until a scattered deck read as a solid one.
  @Test
  func `gathers one altitude per level however differently each column places it`() {
    let atmosphere = PathAtmosphere(
      columns: [
        Fixture.column(distanceNM: 0, surfaceC: 20, altitudeOffsetFt: -80),
        Fixture.column(distanceNM: 10, surfaceC: 10, altitudeOffsetFt: 0),
        Fixture.column(distanceNM: 20, surfaceC: 5, altitudeOffsetFt: 120)
      ],
      providers: .openMeteo
    )
    let altitudesFt = atmosphere.reportedAltitudes.map { $0.converted(to: .feet).value }

    // Three columns of five levels arrive as fifteen altitudes and read back as five.
    #expect(altitudesFt.count == 5)
    for (banded, level) in zip(altitudesFt, [0.0, 3000, 6000, 9000, 12000]) {
      #expect(banded.isApproximatelyEqual(to: level, absoluteTolerance: 100))
    }
  }

  @Test
  func `has nothing to read when no column reported anything`() {
    let empty = PathAtmosphere(columns: [], providers: [])

    #expect(empty.isEmpty)
    #expect(empty.level(atDistanceNM: 0, altitude: .init(value: 1000, unit: .feet)) == nil)
    #expect(empty.freezingAltitude(atDistanceNM: 0) == nil)
  }
}

struct PathAtmosphereFreezingLevelTests {

  @Test
  func `finds where the temperature crosses freezing`() throws {
    // 20 °C at the surface falling two degrees a thousand feet reaches freezing at 10,000 ft.
    let atmosphere = PathAtmosphere(
      columns: [Fixture.column(distanceNM: 0, surfaceC: 20)],
      providers: .openMeteo
    )
    let crossing = try #require(atmosphere.freezingAltitude(atDistanceNM: 0))

    #expect(crossing.isApproximatelyEqual(toFt: 10000))
  }

  /// A single column has to answer for the whole path, or the isotherm collapses to one point and
  /// draws nothing.
  @Test
  func `reports the same freezing level all along a path covered by one column`() throws {
    let atmosphere = PathAtmosphere(
      columns: [Fixture.column(distanceNM: 0, surfaceC: 20)],
      providers: .openMeteo
    )

    for distanceNM in [0.0, 2.5, 18] {
      let crossing = try #require(atmosphere.freezingAltitude(atDistanceNM: distanceNM))
      #expect(crossing.isApproximatelyEqual(toFt: 10000))
    }
  }

  @Test
  func `slopes the freezing level between columns of different temperature`() throws {
    // 20 °C freezes at 10,000 ft; 10 °C at 5,000 ft. Halfway along should freeze at 7,500 ft.
    let atmosphere = PathAtmosphere(
      columns: [
        Fixture.column(distanceNM: 0, surfaceC: 20),
        Fixture.column(distanceNM: 10, surfaceC: 10)
      ],
      providers: .openMeteo
    )
    let crossing = try #require(atmosphere.freezingAltitude(atDistanceNM: 5))

    #expect(crossing.isApproximatelyEqual(toFt: 7500))
  }

  @Test
  func `reports no freezing level for a column that never warms above freezing`() {
    let atmosphere = PathAtmosphere(
      columns: [Fixture.column(distanceNM: 0, surfaceC: -5)],
      providers: .openMeteo
    )

    #expect(atmosphere.freezingAltitude(atDistanceNM: 0) == nil)
  }

  @Test
  func `reports no freezing level for a column that stays above it`() {
    let atmosphere = PathAtmosphere(
      columns: [Fixture.column(distanceNM: 0, surfaceC: 40, lapseRateCPer1000Ft: 1)],
      providers: .openMeteo
    )

    #expect(atmosphere.freezingAltitude(atDistanceNM: 0) == nil)
  }
}

extension Measurement where UnitType == UnitLength {
  /// Whether this altitude reads as the given one, to the foot.
  fileprivate func isApproximatelyEqual(toFt altitudeFt: Double) -> Bool {
    converted(to: .feet).value.isApproximatelyEqual(to: altitudeFt, absoluteTolerance: 1)
  }
}

struct ClimbProfileWindClampingTests {

  /// A profile whose lowest reported wind stands at 3,000 ft, as an FAA bulletin's does.
  private let profile = ClimbProfileGenerator.generate(
    windsAloft: [
      .init(altitudeFt: 3000, temperatureC: 10, windDirectionDeg: 270, windSpeedKts: 25),
      .init(altitudeFt: 6000, temperatureC: 4, windDirectionDeg: 280, windSpeedKts: 35)
    ],
    weightLb: 5500,
    aircraftType: .g2(updatedThrustSchedule: true),
    seaLevelPressureInHg: 29.92,
    useRegressionModel: true
  )

  @Test
  func `carries the lowest reported wind down to the ground rather than fading to calm`() throws {
    // The band a departure actually climbs through, below anything a bulletin reports.
    for altitudeFt in [0.0, 500, 1500, 2999] {
      #expect(try #require(profile.windSpeed(at: altitudeFt)) == 25)
      #expect(try #require(profile.windDirection(at: altitudeFt)) == 270)
    }
  }

  @Test
  func `interpolates between reported levels`() throws {
    #expect(
      try #require(profile.windSpeed(at: 4500)).isApproximatelyEqual(
        to: 30,
        absoluteTolerance: 0.01
      )
    )
  }
}
