import CoreLocation
import RealModule
import Testing

@testable import SF50_Shared

// MARK: - NearbyFinder Tests

struct NearbyFinderTests {

  @Test
  func `bounding box calculation`() {
    let center = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let bounds = NearbyFinder.boundingBox(center: center, radiusNM: 60.0)

    // 60nm ≈ 1 degree of latitude
    #expect(bounds.minLat.isApproximatelyEqual(to: 36.0, relativeTolerance: 0.01))
    #expect(bounds.maxLat.isApproximatelyEqual(to: 38.0, relativeTolerance: 0.01))

    // Longitude delta varies with latitude, at 37°N should be slightly larger than 1°
    let expectedLonDelta = 60.0 / (60.0 * cos(37.0 * .pi / 180.0))
    #expect(
      bounds.minLon.isApproximatelyEqual(to: -122.0 - expectedLonDelta, relativeTolerance: 0.01)
    )
    #expect(
      bounds.maxLon.isApproximatelyEqual(to: -122.0 + expectedLonDelta, relativeTolerance: 0.01)
    )
  }

  @Test
  func `find nearby items`() {
    struct TestItem: Locatable {
      let id: String
      let coordinate: CLLocationCoordinate2D
    }

    let items = [
      // At center
      TestItem(id: "A", coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)),
      // ~30nm north
      TestItem(id: "B", coordinate: CLLocationCoordinate2D(latitude: 37.5, longitude: -122.0)),
      // ~60nm north
      TestItem(id: "C", coordinate: CLLocationCoordinate2D(latitude: 38.0, longitude: -122.0)),
      // ~180nm north
      TestItem(id: "D", coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: -122.0))
    ]

    let center = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let nearby = NearbyFinder.find(near: center, in: items, radiusNM: 100.0, limit: 10)

    #expect(nearby.count == 3)  // A, B, C within 100nm
    #expect(nearby[0].item.id == "A")  // Closest first
    #expect(nearby[0].distanceNM < 1.0)  // At center, essentially 0
    #expect(nearby[1].item.id == "B")
    #expect(nearby[2].item.id == "C")
  }

  @Test
  func `find nearby with limit`() {
    struct TestItem: Locatable {
      let id: String
      let coordinate: CLLocationCoordinate2D
    }

    let items = [
      TestItem(id: "A", coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)),
      TestItem(id: "B", coordinate: CLLocationCoordinate2D(latitude: 37.1, longitude: -122.0)),
      TestItem(id: "C", coordinate: CLLocationCoordinate2D(latitude: 37.2, longitude: -122.0)),
      TestItem(id: "D", coordinate: CLLocationCoordinate2D(latitude: 37.3, longitude: -122.0))
    ]

    let center = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let nearby = NearbyFinder.find(near: center, in: items, radiusNM: 100.0, limit: 2)

    #expect(nearby.count == 2)  // Limited to 2
    #expect(nearby[0].item.id == "A")
    #expect(nearby[1].item.id == "B")
  }
}

// MARK: - WindsAloftData Altitude Interpolation Tests

struct WindsAloftAltitudeInterpolationTests {

  @Test
  func `interpolate between levels`() {
    let data = makeTestData(entries: [
      (altitude: 3000, direction: 270, speed: 10, temp: 10),
      (altitude: 6000, direction: 270, speed: 20, temp: 0),
      (altitude: 9000, direction: 270, speed: 30, temp: -10)
    ])

    // Interpolate at 4500ft (halfway between 3000 and 6000)
    let entry = data.entry(at: .init(value: 4500, unit: .feet))

    #expect(entry != nil)
    #expect(
      entry?.windSpeed.converted(to: .knots).value.isApproximatelyEqual(
        to: 15.0,
        relativeTolerance: 0.01
      ) == true
    )
    #expect(
      entry?.temperature?.converted(to: .celsius).value.isApproximatelyEqual(
        to: 5.0,
        relativeTolerance: 0.01
      ) == true
    )
  }

  @Test
  func `interpolate below lowest`() {
    let data = makeTestData(entries: [
      (altitude: 3000, direction: 270, speed: 10, temp: 10),
      (altitude: 6000, direction: 270, speed: 20, temp: 0)
    ])

    // Below lowest level - should return lowest entry
    let entry = data.entry(at: .init(value: 1000, unit: .feet))

    #expect(entry != nil)
    #expect(
      entry?.windSpeed.converted(to: .knots).value.isApproximatelyEqual(
        to: 10.0,
        relativeTolerance: 0.01
      ) == true
    )
    #expect(entry?.altitude.converted(to: .feet).value == 3000)
  }

  @Test
  func `interpolate above highest`() {
    let data = makeTestData(entries: [
      (altitude: 3000, direction: 270, speed: 10, temp: 10),
      (altitude: 6000, direction: 270, speed: 20, temp: 0)
    ])

    // Above highest level - should return highest entry
    let entry = data.entry(at: .init(value: 10000, unit: .feet))

    #expect(entry != nil)
    #expect(
      entry?.windSpeed.converted(to: .knots).value.isApproximatelyEqual(
        to: 20.0,
        relativeTolerance: 0.01
      ) == true
    )
    #expect(entry?.altitude.converted(to: .feet).value == 6000)
  }

  @Test
  func `interpolate exact altitude`() {
    let data = makeTestData(entries: [
      (altitude: 3000, direction: 270, speed: 10, temp: 10),
      (altitude: 6000, direction: 270, speed: 20, temp: 0)
    ])

    // Exact match - should return that entry's values
    let entry = data.entry(at: .init(value: 3000, unit: .feet))

    #expect(entry != nil)
    #expect(
      entry?.windSpeed.converted(to: .knots).value.isApproximatelyEqual(
        to: 10.0,
        relativeTolerance: 0.01
      ) == true
    )
  }

  @Test
  func `interpolate direction across the 360 boundary`() {
    let data = makeTestData(entries: [
      (altitude: 3000, direction: 350, speed: 10, temp: 10),
      (altitude: 6000, direction: 10, speed: 10, temp: 0)
    ])

    // Interpolate at 4500ft - should go through 360° not through 180°
    let entry = data.entry(at: .init(value: 4500, unit: .feet))

    #expect(entry != nil)
    // Halfway between 350° and 10° should be 0° (or 360°)
    let direction = entry?.windDirection?.converted(to: .degrees).value ?? -999
    #expect(
      direction.isApproximatelyEqual(to: 0.0, absoluteTolerance: 1.0)
        || direction.isApproximatelyEqual(to: 360.0, absoluteTolerance: 1.0)
    )
  }

  @Test
  func `interpolate direction shortest path`() {
    let data = makeTestData(entries: [
      (altitude: 3000, direction: 90, speed: 10, temp: 10),
      (altitude: 6000, direction: 180, speed: 10, temp: 0)
    ])

    // Interpolate at 4500ft - halfway between 90° and 180° should be 135°
    let entry = data.entry(at: .init(value: 4500, unit: .feet))

    #expect(entry != nil)
    #expect(
      entry?.windDirection?.converted(to: .degrees).value.isApproximatelyEqual(
        to: 135.0,
        relativeTolerance: 0.01
      ) == true
    )
  }

  @Test
  func `interpolate with light and variable`() {
    let data = makeTestDataWithLV(entries: [
      (altitude: 3000, direction: nil, speed: nil, temp: 10),  // L&V: nil direction, 0 speed
      (altitude: 6000, direction: 270, speed: 20, temp: 0)
    ])

    // Interpolate at 4500ft - L&V treated as 0 knots
    let entry = data.entry(at: .init(value: 4500, unit: .feet))

    #expect(entry != nil)
    // Halfway between 0 and 20 knots
    #expect(
      entry?.windSpeed.converted(to: .knots).value.isApproximatelyEqual(
        to: 10.0,
        relativeTolerance: 0.01
      ) == true
    )
    // Direction should come from the non-L&V entry
    #expect(
      entry?.windDirection?.converted(to: .degrees).value.isApproximatelyEqual(
        to: 270.0,
        relativeTolerance: 0.01
      ) == true
    )
  }

  @Test
  func `empty data returns nil`() {
    let data = makeTestData(entries: [])
    let entry = data.entry(at: .init(value: 5000, unit: .feet))
    #expect(entry == nil)
  }

  // MARK: - Test Helpers

  private func makeTestData(entries: [(altitude: Int, direction: Int, speed: Int, temp: Int)])
    -> WindsAloftData
  {
    let entryObjects = entries.map { e in
      WindsAloftData.Entry(
        altitude: .init(value: Double(e.altitude), unit: .feet),
        windDirection: .init(value: Double(e.direction), unit: .degrees),
        windSpeed: .init(value: Double(e.speed), unit: .knots),
        temperature: .init(value: Double(e.temp), unit: .celsius)
      )
    }
    return WindsAloftData(entries: entryObjects)
  }

  private func makeTestDataWithLV(
    entries: [(altitude: Int, direction: Int?, speed: Int?, temp: Int)]
  ) -> WindsAloftData {
    let entryObjects = entries.map { e in
      WindsAloftData.Entry(
        altitude: .init(value: Double(e.altitude), unit: .feet),
        windDirection: e.direction.map { .init(value: Double($0), unit: .degrees) },
        windSpeed: .init(value: Double(e.speed ?? 0), unit: .knots),
        temperature: .init(value: Double(e.temp), unit: .celsius)
      )
    }
    return WindsAloftData(entries: entryObjects)
  }
}

// MARK: - WindsAloftInterpolator Spatial Interpolation Tests

struct WindsAloftSpatialInterpolationTests {

  @Test
  func `interpolate from multiple stations`() {
    // WindsAloftInterpolator is a caseless enum used as a namespace

    // Create two stations equidistant from target
    let stations = [
      makeStation(id: "A", lat: 37.1, lon: -122.0, direction: 270, speed: 10),
      makeStation(id: "B", lat: 36.9, lon: -122.0, direction: 270, speed: 20)
    ]

    let target = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let entry = WindsAloftInterpolator.interpolate(
      at: target,
      altitude: .init(value: 6000, unit: .feet),
      from: stations
    )

    #expect(entry != nil)
    // Roughly equidistant, so should average to ~15 knots
    #expect(
      entry?.windSpeed.converted(to: .knots).value.isApproximatelyEqual(
        to: 15.0,
        relativeTolerance: 0.1
      ) == true
    )
  }

  @Test
  func `use closest station when very close`() {
    // WindsAloftInterpolator is a caseless enum used as a namespace

    // One station very close, one far
    let stations = [
      makeStation(id: "A", lat: 37.001, lon: -122.0, direction: 270, speed: 10),  // Very close
      makeStation(id: "B", lat: 38.0, lon: -122.0, direction: 270, speed: 50)  // Far
    ]

    let target = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let entry = WindsAloftInterpolator.interpolate(
      at: target,
      altitude: .init(value: 6000, unit: .feet),
      from: stations
    )

    #expect(entry != nil)
    // Should use station A directly since it's within 5nm threshold
    #expect(
      entry?.windSpeed.converted(to: .knots).value.isApproximatelyEqual(
        to: 10.0,
        relativeTolerance: 0.01
      ) == true
    )
  }

  @Test
  func `return nil when no stations in range`() {
    // WindsAloftInterpolator is a caseless enum used as a namespace

    // All stations far away
    let stations = [
      makeStation(id: "A", lat: 40.0, lon: -122.0, direction: 270, speed: 10),
      makeStation(id: "B", lat: 35.0, lon: -122.0, direction: 270, speed: 20)
    ]

    let target = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let config = WindsAloftInterpolator.Configuration(maxDistanceNM: 50.0)  // Only 50nm range

    let entry = WindsAloftInterpolator.interpolate(
      at: target,
      altitude: .init(value: 6000, unit: .feet),
      from: stations,
      configuration: config
    )

    #expect(entry == nil)
  }

  @Test
  func `use single station when only one available`() {
    // WindsAloftInterpolator is a caseless enum used as a namespace

    let stations = [
      makeStation(id: "A", lat: 37.5, lon: -122.0, direction: 270, speed: 25)
    ]

    let target = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let entry = WindsAloftInterpolator.interpolate(
      at: target,
      altitude: .init(value: 6000, unit: .feet),
      from: stations
    )

    #expect(entry != nil)
    #expect(
      entry?.windSpeed.converted(to: .knots).value.isApproximatelyEqual(
        to: 25.0,
        relativeTolerance: 0.01
      ) == true
    )
  }

  @Test
  func `opposing winds fall back to the nearest station`() throws {
    let stations = [
      makeStation(id: "A", lat: 37.1, lon: -122.0, direction: 0, speed: 10),
      makeStation(id: "B", lat: 36.9, lon: -122.0, direction: 180, speed: 10)
    ]

    let target = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let entry = try #require(
      WindsAloftInterpolator.interpolate(
        at: target,
        altitude: .init(value: 6000, unit: .feet),
        from: stations
      )
    )

    // A wind shift lying between two stations blowing 10 kt leaves no resultant to report, but it
    // is not calm either: the nearest station's own forecast stands rather than a fabricated calm.
    #expect(entry.windSpeed.converted(to: .knots).value.isApproximatelyEqual(to: 10))
    let direction = try #require(entry.windDirection).converted(to: .degrees).value
    #expect(direction.isApproximatelyEqual(to: 0) || direction.isApproximatelyEqual(to: 180))
  }

  @Test
  func `light and variable stations interpolate to calm`() {
    let stations = [
      makeStation(id: "A", lat: 37.1, lon: -122.0, direction: nil, speed: 0),
      makeStation(id: "B", lat: 36.9, lon: -122.0, direction: nil, speed: 0)
    ]

    let target = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let entry = WindsAloftInterpolator.interpolate(
      at: target,
      altitude: .init(value: 6000, unit: .feet),
      from: stations
    )

    // Neighbours that are themselves calm genuinely leave a calm point between them, which is a
    // different thing from neighbours whose winds cancel.
    #expect(entry?.windSpeed.converted(to: .knots).value == 0)
    #expect(entry?.windDirection == nil)
  }

  @Test
  func `perpendicular winds resolve to their vector sum`() throws {
    let stations = [
      makeStation(id: "A", lat: 37.1, lon: -122.0, direction: 0, speed: 10),
      makeStation(id: "B", lat: 36.9, lon: -122.0, direction: 270, speed: 10)
    ]

    let target = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let entry = try #require(
      WindsAloftInterpolator.interpolate(
        at: target,
        altitude: .init(value: 6000, unit: .feet),
        from: stations
      )
    )

    // A 10 kt northerly and a 10 kt westerly, equally weighted, average to a 7.07 kt
    // wind from 315°.
    #expect(
      entry.windSpeed.converted(to: .knots).value.isApproximatelyEqual(
        to: 10 / 2.0.squareRoot(),
        relativeTolerance: 0.05
      )
    )
    let direction = try #require(entry.windDirection)
    #expect(
      direction.converted(to: .degrees).value.isApproximatelyEqual(
        to: 315,
        relativeTolerance: 0.02
      )
    )
  }

  @Test
  func `stations do not contribute at altitudes they do not report`() {
    // A station on high terrain publishes nothing below 9,000 ft, because the bulletin omits
    // levels within 1,500 ft of a station's elevation.
    let lowland = makeStation(id: "LOW", lat: 37.5, lon: -122.0, direction: 270, speed: 10)
    let plateau = WindsAloftInterpolator.LocatedStation(
      stationID: "HIGH",
      coordinate: .init(latitude: 36.5, longitude: -122.0),
      data: .init(entries: [
        .init(
          altitude: .init(value: 9000, unit: .feet),
          windDirection: .init(value: 90, unit: .degrees),
          windSpeed: .init(value: 90, unit: .knots),
          temperature: nil
        )
      ])
    )

    let target = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let entry = WindsAloftInterpolator.interpolate(
      at: target,
      altitude: .init(value: 6000, unit: .feet),
      from: [lowland, plateau]
    )

    // Only the lowland station reports 6,000 ft, so the plateau's 9,000 ft wind must not be
    // clamped down and blended in.
    #expect(entry != nil)
    #expect(
      entry?.windSpeed.converted(to: .knots).value.isApproximatelyEqual(
        to: 10.0,
        relativeTolerance: 0.01
      ) == true
    )
  }

  @Test
  func `IDW weighting favors closer stations`() {
    // WindsAloftInterpolator is a caseless enum used as a namespace

    // Station A is much closer than Station B
    let stations = [
      makeStation(id: "A", lat: 37.1, lon: -122.0, direction: 270, speed: 10),  // ~6nm away
      makeStation(id: "B", lat: 38.0, lon: -122.0, direction: 270, speed: 100)  // ~60nm away
    ]

    let target = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let entry = WindsAloftInterpolator.interpolate(
      at: target,
      altitude: .init(value: 6000, unit: .feet),
      from: stations
    )

    #expect(entry != nil)
    // With IDW power=2, closer station should dominate significantly
    // Station A is ~10x closer, so weight ratio is ~100:1
    // Expected speed much closer to 10 than 100
    let speed = entry?.windSpeed.converted(to: .knots).value ?? 0
    #expect(speed < 20.0)  // Should be much closer to 10 than 100
  }

  // MARK: - Test Helpers

  private func makeStation(id: String, lat: Double, lon: Double, direction: Int?, speed: Int)
    -> WindsAloftInterpolator.LocatedStation
  {
    let entry = WindsAloftData.Entry(
      altitude: .init(value: 6000, unit: .feet),
      windDirection: direction.map { .init(value: Double($0), unit: .degrees) },
      windSpeed: .init(value: Double(speed), unit: .knots),
      temperature: .init(value: 0, unit: .celsius)
    )
    let data = WindsAloftData(entries: [entry])
    return WindsAloftInterpolator.LocatedStation(
      stationID: id,
      coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
      data: data
    )
  }
}

// MARK: - Published Forecast Location Table Tests

/// The station table is transcribed by hand from a PDF whose text layer is defective in places, so
/// it is checked rather than trusted.
struct WindsAloftStationTableTests {

  @Test
  func `table covers every published forecast location`() {
    #expect(WindsAloftStation.all.count == 233)
  }

  /// Spot-checks the kinds of location the table has to carry: an airport, a VOR with no airport,
  /// and an oceanic grid point that is neither.
  @Test(
    arguments: [
      (id: "SFO", latitude: 37.616667, longitude: -122.366667),
      (id: "EMI", latitude: 39.483333, longitude: -76.966667),
      (id: "H51", latitude: 26.5, longitude: -95.0)
    ]
  )
  func `stations sit where the directive says they do`(
    expected: (id: String, latitude: Double, longitude: Double)
  ) throws {
    let station = try #require(WindsAloftStation.all[expected.id])

    #expect(station.latitude.isApproximatelyEqual(to: expected.latitude, absoluteTolerance: 1e-5))
    #expect(station.longitude.isApproximatelyEqual(to: expected.longitude, absoluteTolerance: 1e-5))
  }

  /// Three rows are wrong in the directive itself: Berlin's and one Gulf of Alaska point's
  /// longitudes are printed without their minus signs, putting them in Mongolia and west of Attu,
  /// and San Antonio's latitude is 54 NM south of the field.
  @Test
  func `rows wrong in the directive are corrected`() throws {
    let berlin = try #require(WindsAloftStation.all["BML"])
    #expect(berlin.longitude < 0)
    #expect(berlin.longitude.isApproximatelyEqual(to: -71.183333, absoluteTolerance: 1e-5))

    let gulfOfAlaska = try #require(WindsAloftStation.all["5AB"])
    #expect(gulfOfAlaska.longitude < 0)
    #expect(gulfOfAlaska.longitude.isApproximatelyEqual(to: -176, absoluteTolerance: 1e-5))

    let sanAntonio = try #require(WindsAloftStation.all["SAT"])
    #expect(sanAntonio.latitude.isApproximatelyEqual(to: 29.533333, absoluteTolerance: 1e-5))
  }
}

// MARK: - Bulletin Interpolation Tests

/// The path the app actually takes: a bulletin keyed by station identifier, resolved against the
/// bundled table and interpolated for an airport that has no forecast of its own.
struct WindsAloftBulletinInterpolationTests {

  @Test
  func `airport between stations gets an interpolated column`() throws {
    // Oakland has no forecast location of its own, and sits between the San Francisco,
    // Sacramento and Fresno stations.
    let result = try #require(
      WindsAloftInterpolator.interpolate(
        at: .init(latitude: 37.7213, longitude: -122.2207),
        in: bulletin(stations: ["SFO": 20, "SAC": 30, "FAT": 40])
      )
    )

    #expect(result.source == .interpolated)
    #expect(!result.data.entries.isEmpty)

    let speed = try #require(result.data.entry(at: .init(value: 6000, unit: .feet)))
      .windSpeed.converted(to: .knots).value
    // San Francisco is much the closest, so it dominates without the others being ignored.
    #expect(speed > 20 && speed < 26)
  }

  @Test
  func `airport beyond every station gets nothing`() {
    // Mid-Pacific, thousands of miles from any of these stations.
    let result = WindsAloftInterpolator.interpolate(
      at: .init(latitude: 30.0, longitude: -160.0),
      in: bulletin(stations: ["SFO": 20, "SAC": 30, "FAT": 40])
    )

    #expect(result?.source == nil)
  }

  /// A station identifier the bundled table doesn't know contributes nothing, rather than being
  /// placed at some default position.
  @Test
  func `unknown stations are ignored`() {
    let result = WindsAloftInterpolator.interpolate(
      at: .init(latitude: 37.7213, longitude: -122.2207),
      in: bulletin(stations: ["ZZZ": 20, "QQQ": 30])
    )

    #expect(result?.source == nil)
  }

  private func bulletin(stations: [String: Int]) -> WindsAloftBulletin {
    .init(
      validAt: .now,
      usePeriod: .init(start: .now, duration: 3600),
      stations: stations.mapValues { speed in
        WindsAloftData(entries: [
          .init(
            altitude: .init(value: 3000, unit: .feet),
            windDirection: .init(value: 270, unit: .degrees),
            windSpeed: .init(value: Double(speed), unit: .knots),
            temperature: nil
          ),
          .init(
            altitude: .init(value: 9000, unit: .feet),
            windDirection: .init(value: 270, unit: .degrees),
            windSpeed: .init(value: Double(speed), unit: .knots),
            temperature: nil
          )
        ])
      }
    )
  }
}
