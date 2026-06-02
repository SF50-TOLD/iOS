import CoreLocation
import RealModule
import Testing

@testable import SF50_Shared

// MARK: - NearbyFinder Tests

struct NearbyFinderTests {

  @Test
  func boundingBoxCalculation() {
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
  func findNearbyItems() {
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
    let nearby = NearbyFinder.find(near: center, in: items, radius: 100.0, limit: 10)

    #expect(nearby.count == 3)  // A, B, C within 100nm
    #expect(nearby[0].item.id == "A")  // Closest first
    #expect(nearby[0].distanceNM < 1.0)  // At center, essentially 0
    #expect(nearby[1].item.id == "B")
    #expect(nearby[2].item.id == "C")
  }

  @Test
  func findNearbyWithLimit() {
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
    let nearby = NearbyFinder.find(near: center, in: items, radius: 100.0, limit: 2)

    #expect(nearby.count == 2)  // Limited to 2
    #expect(nearby[0].item.id == "A")
    #expect(nearby[1].item.id == "B")
  }
}

// MARK: - WindsAloftData Altitude Interpolation Tests

struct WindsAloftAltitudeInterpolationTests {

  @Test
  func interpolateBetweenLevels() {
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
  func interpolateBelowLowest() {
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
  func interpolateAboveHighest() {
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
  func interpolateExactAltitude() {
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
  func interpolateDirectionAcross360Boundary() {
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
  func interpolateDirectionShortestPath() {
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
  func interpolateWithLightAndVariable() {
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
  func emptyDataReturnsNil() {
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
    return WindsAloftData(stationID: "TEST", entries: entryObjects)
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
    return WindsAloftData(stationID: "TEST", entries: entryObjects)
  }
}

// MARK: - WindsAloftInterpolator Spatial Interpolation Tests

struct WindsAloftSpatialInterpolationTests {

  @Test
  func interpolateFromMultipleStations() {
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
  func useClosestStationWhenVeryClose() {
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
  func returnNilWhenNoStationsInRange() {
    // WindsAloftInterpolator is a caseless enum used as a namespace

    // All stations far away
    let stations = [
      makeStation(id: "A", lat: 40.0, lon: -122.0, direction: 270, speed: 10),
      makeStation(id: "B", lat: 35.0, lon: -122.0, direction: 270, speed: 20)
    ]

    let target = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let config = WindsAloftInterpolator.Configuration(maxDistance: 50.0)  // Only 50nm range

    let entry = WindsAloftInterpolator.interpolate(
      at: target,
      altitude: .init(value: 6000, unit: .feet),
      from: stations,
      configuration: config
    )

    #expect(entry == nil)
  }

  @Test
  func useSingleStationWhenOnlyOneAvailable() {
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
  func interpolateDirectionWithUnitVectors() {
    // WindsAloftInterpolator is a caseless enum used as a namespace

    // Two stations with opposite winds - unit vector averaging should handle this
    let stations = [
      makeStation(id: "A", lat: 37.1, lon: -122.0, direction: 0, speed: 10),  // North wind
      makeStation(id: "B", lat: 36.9, lon: -122.0, direction: 180, speed: 10)  // South wind
    ]

    let target = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
    let entry = WindsAloftInterpolator.interpolate(
      at: target,
      altitude: .init(value: 6000, unit: .feet),
      from: stations
    )

    #expect(entry != nil)
    // Opposite winds should result in near-zero resultant or indeterminate direction
    // Speed should still average to 10 knots
    #expect(
      entry?.windSpeed.converted(to: .knots).value.isApproximatelyEqual(
        to: 10.0,
        relativeTolerance: 0.1
      ) == true
    )
  }

  @Test
  func idwWeightingFavorsCloserStations() {
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

  private func makeStation(id: String, lat: Double, lon: Double, direction: Int, speed: Int)
    -> WindsAloftInterpolator.LocatedStation
  {
    let entry = WindsAloftData.Entry(
      altitude: .init(value: 6000, unit: .feet),
      windDirection: .init(value: Double(direction), unit: .degrees),
      windSpeed: .init(value: Double(speed), unit: .knots),
      temperature: .init(value: 0, unit: .celsius)
    )
    let data = WindsAloftData(stationID: id, entries: [entry])
    return WindsAloftInterpolator.LocatedStation(
      stationID: id,
      coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
      data: data
    )
  }
}
