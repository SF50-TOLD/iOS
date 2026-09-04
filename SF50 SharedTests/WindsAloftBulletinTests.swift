import CoreLocation
import Foundation
import SwiftMETAR
import Testing

@testable import SF50_Shared

/// The three bulletins of a single 12Z issuance, as the NWS publishes them.
private enum Issuance {
  static let referenceDate = zulu(day: 12, hour: 13, minute: 59)

  static let sixHour = (
    productID: "FBUS31", bulletinID: "FD1US1", valid: "121800Z",
    forUse: "1400-2100Z"
  )
  static let twelveHour = (
    productID: "FBUS33", bulletinID: "FD3US3", valid: "130000Z",
    forUse: "2100-0600Z"
  )
  static let twentyFourHour = (
    productID: "FBUS35", bulletinID: "FD5US5", valid: "131200Z",
    forUse: "0600-1800Z"
  )

  static func zulu(day: Int, hour: Int, minute: Int = 0) -> Date {
    var components = DateComponents()
    components.timeZone = .gmt
    components.year = 2026
    components.month = 8
    components.day = day
    components.hour = hour
    components.minute = minute
    return Calendar(identifier: .gregorian).date(from: components)!
  }

  static func bulletin(
    _ product: (productID: String, bulletinID: String, valid: String, forUse: String)
  ) async throws -> WindsAloftBulletin {
    let text = """
      000
      \(product.productID) KWNO 121359
      \(product.bulletinID)
      DATA BASED ON 121200Z
      VALID \(product.valid)   FOR USE \(product.forUse). TEMPS NEG ABV 24000

      FT  3000    6000    9000   12000   18000   24000  30000  34000  39000
      SFO 1813 2011+20 2014+14 2116+08 1907-09 1707-21 181037 191346 212452
      """
    let parsed = try await WindsAloft.from(string: text, on: referenceDate)
    return try #require(WindsAloftBulletin(from: parsed))
  }
}

/// The regional products of a single forecast period, abridged to the rows that carry their
/// format differences.
///
/// Every region publishes the same valid time and use period for a given forecast hour. Hawaii and
/// the Pacific add levels below 3,000 feet and stop at 24,000, and the Pacific bulletin omits the
/// blank line the others leave before the `FT` header.
private enum Regions {
  static let CONUS = """
    000
    FBUS31 KWNO 121359
    FD1US1
    DATA BASED ON 121200Z
    VALID 121800Z   FOR USE 1400-2100Z. TEMPS NEG ABV 24000

    FT  3000    6000    9000   12000   18000   24000  30000  34000  39000
    SFO 1813 2011+20 2014+14 2116+08 1907-09 1707-21 181037 191346 212452
    """

  static let alaska = """
    000
    FBAK31 KWNO 121359
    FD1AK1
    DATA BASED ON 121200Z
    VALID 121800Z   FOR USE 1400-2100Z. TEMPS NEG ABV 24000

    FT  3000    6000    9000   12000   18000   24000  30000  34000  39000
    ANC 2313 2411+02 2514-04 2616-10 2718-25 2820-38 283052 284058 285062
    """

  static let hawaii = """
    000
    FBHW31 KWNO 121359
    FD1HW1
    DATA BASED ON 121200Z
    VALID 121800Z   FOR USE 1400-2100Z. TEMPS NEG ABV 24000

    FT  1000 1500 2000 3000    6000    9000   12000   15000   18000   24000
    HNL 0618 0622 0725 0823 0913+15 0913+13 1014+07 1014+04 1220-01 1109-13
    """

  static let pacific = """
    000
    FBOC31 KWNO 121359
    FD1OC1
    DATA BASED ON 121200Z
    VALID 121800Z   FOR USE 1400-2100Z. TEMPS NEG ABV 24000
    FT  1000 1500 2000 3000    6000    9000   12000   15000   18000   24000
    GUM 1315 1316 1316 1317 1114+16 0811+12 0811+07 0816+02 0822-05 1014-14
    """

  static func bulletin(_ text: String) async throws -> WindsAloftBulletin {
    let parsed = try await WindsAloft.from(string: text, on: Issuance.referenceDate)
    return try #require(WindsAloftBulletin(from: parsed))
  }
}

struct WindsAloftBulletinTests {

  /// The `FOR USE` period is given only as times of day and brackets the valid time, so the
  /// 12-hour bulletin's period starts the day before the day it is valid.
  @Test
  func `use period brackets valid time`() async throws {
    let bulletin = try await Issuance.bulletin(Issuance.twelveHour)

    #expect(bulletin.validAt == Issuance.zulu(day: 13, hour: 0))
    #expect(bulletin.usePeriod.start == Issuance.zulu(day: 12, hour: 21))
    #expect(bulletin.usePeriod.end == Issuance.zulu(day: 13, hour: 6))
  }
}

/// The four regional products differ in their level sets and their headers, and all four have to
/// parse for the whole country to be covered.
struct WindsAloftRegionParsingTests {

  @Test(arguments: [Regions.CONUS, Regions.alaska, Regions.hawaii, Regions.pacific])
  func `every region parses`(text: String) async throws {
    let bulletin = try await Regions.bulletin(text)

    #expect(bulletin.validAt == Issuance.zulu(day: 12, hour: 18))
    #expect(bulletin.stations.count == 1)
  }

  @Test
  func `hawaii and the Pacific report their extra low levels`() async throws {
    for text in [Regions.hawaii, Regions.pacific] {
      let bulletin = try await Regions.bulletin(text)
      let data = try #require(bulletin.stations.values.first)
      let altitudesFt = Set(data.entries.map { $0.altitude.converted(to: .feet).value })

      #expect(altitudesFt.isSuperset(of: [1000, 1500, 2000, 15000]))
      #expect(altitudesFt.max() == 24000)
    }
  }

  @Test
  func `CONUS and Alaska reach the high levels`() async throws {
    for text in [Regions.CONUS, Regions.alaska] {
      let bulletin = try await Regions.bulletin(text)
      let data = try #require(bulletin.stations.values.first)
      let altitudesFt = Set(data.entries.map { $0.altitude.converted(to: .feet).value })

      #expect(altitudesFt.min() == 3000)
      #expect(altitudesFt.max() == 39000)
    }
  }
}

/// An airport takes a station's report as its own only when the station is actually near it.
struct WindsAloftReportingStationTests {
  private let bulletin: WindsAloftBulletin

  init() async throws {
    bulletin = try await Regions.bulletin(Regions.CONUS)
  }

  @Test
  func `airport at its own station is a report`() throws {
    // San Francisco International, 0.2 NM from the forecast location of the same identifier.
    let reported = try #require(
      WeatherLoader.reportedData(
        stationID: "SFO",
        at: .init(latitude: 37.61961, longitude: -122.36561),
        in: bulletin
      )
    )

    #expect(reported.source == .station("SFO"))
  }

  /// The NWS often forecasts for the VOR rather than the field, so a station a few miles off is
  /// still that airport's own report.
  @Test
  func `station offset to the VOR is still a report`() throws {
    // Roughly the separation between Denver International and the DEN forecast location.
    let reported = WeatherLoader.reportedData(
      stationID: "SFO",
      at: .init(latitude: 37.79, longitude: -122.36561),
      in: bulletin
    )

    #expect(reported?.source == .station("SFO"))
  }

  /// Location identifiers and forecast-location identifiers are separate namespaces, and an
  /// airport sharing an identifier with a distant forecast location must not inherit its winds.
  @Test
  func `distant station sharing the identifier is rejected`() {
    let reported = WeatherLoader.reportedData(
      stationID: "SFO",
      at: .init(latitude: 40.0, longitude: -105.0),
      in: bulletin
    )

    #expect(reported?.source == nil)
  }

  @Test
  func `airport with no station of its own has no report`() {
    #expect(
      WeatherLoader.reportedData(
        stationID: "OAK",
        at: .init(latitude: 37.7213, longitude: -122.2207),
        in: bulletin
      )?.source == nil
    )
  }
}

/// Each region publishes a period separately, so the regions covering one period are folded back
/// into a single bulletin.
struct WindsAloftBulletinMergingTests {

  @Test
  func `regions covering the same period become one bulletin`() async throws {
    let merged = WindsAloftBulletin.merged([
      try await Regions.bulletin(Regions.CONUS),
      try await Regions.bulletin(Regions.alaska),
      try await Regions.bulletin(Regions.hawaii),
      try await Regions.bulletin(Regions.pacific)
    ])

    let bulletin = try #require(merged.first)
    #expect(merged.count == 1)
    #expect(Set(bulletin.stations.keys) == ["SFO", "ANC", "HNL", "GUM"])
  }

  /// Periods are grouped rather than assumed to agree, so a product covering a different period
  /// stays its own bulletin instead of being folded into one it doesn't belong to.
  @Test
  func `bulletins for different periods stay separate`() async throws {
    let merged = WindsAloftBulletin.merged([
      try await Regions.bulletin(Regions.CONUS),
      try await Issuance.bulletin(Issuance.twelveHour)
    ])

    #expect(merged.count == 2)
    #expect(merged.map(\.validAt) == merged.map(\.validAt).sorted())
  }
}

struct WindsAloftBulletinSelectionTests {
  private let bulletins: [WindsAloftBulletin]

  init() async throws {
    bulletins = [
      try await Issuance.bulletin(Issuance.sixHour),
      try await Issuance.bulletin(Issuance.twelveHour),
      try await Issuance.bulletin(Issuance.twentyFourHour)
    ]
  }

  @Test
  func `selects the bulletin published for the time`() throws {
    let sixHour = try #require(
      WeatherLoader.bulletins(for: Issuance.zulu(day: 12, hour: 16), in: bulletins).first
    )
    #expect(sixHour.validAt == Issuance.zulu(day: 12, hour: 18))

    let twelveHour = try #require(
      WeatherLoader.bulletins(for: Issuance.zulu(day: 13, hour: 2), in: bulletins).first
    )
    #expect(twelveHour.validAt == Issuance.zulu(day: 13, hour: 0))

    let twentyFourHour = try #require(
      WeatherLoader.bulletins(for: Issuance.zulu(day: 13, hour: 15), in: bulletins).first
    )
    #expect(twentyFourHour.validAt == Issuance.zulu(day: 13, hour: 12))
  }

  /// Consecutive use periods share an endpoint; the earlier bulletin wins it.
  @Test
  func `selects the earlier bulletin at a shared boundary`() throws {
    let bulletin = try #require(
      WeatherLoader.bulletins(for: Issuance.zulu(day: 12, hour: 21), in: bulletins).first
    )

    #expect(bulletin.validAt == Issuance.zulu(day: 12, hour: 18))
  }

  @Test
  func `has no bulletin outside every use period`() {
    #expect(WeatherLoader.bulletins(for: Issuance.zulu(day: 15, hour: 12), in: bulletins).isEmpty)
    #expect(WeatherLoader.bulletins(for: Issuance.zulu(day: 12, hour: 10), in: bulletins).isEmpty)
  }
}
