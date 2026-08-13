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

struct WindsAloftBulletinTests {

  /// The `FOR USE` period is given only as times of day and brackets the valid time, so the
  /// 12-hour bulletin's period starts the day before the day it is valid.
  @Test
  func usePeriodBracketsValidTime() async throws {
    let bulletin = try await Issuance.bulletin(Issuance.twelveHour)

    #expect(bulletin.validAt == Issuance.zulu(day: 13, hour: 0))
    #expect(bulletin.usePeriod.start == Issuance.zulu(day: 12, hour: 21))
    #expect(bulletin.usePeriod.end == Issuance.zulu(day: 13, hour: 6))
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
  func selectsTheBulletinPublishedForTheTime() throws {
    let sixHour = try #require(
      WeatherLoader.bulletin(for: Issuance.zulu(day: 12, hour: 16), in: bulletins)
    )
    #expect(sixHour.validAt == Issuance.zulu(day: 12, hour: 18))

    let twelveHour = try #require(
      WeatherLoader.bulletin(for: Issuance.zulu(day: 13, hour: 2), in: bulletins)
    )
    #expect(twelveHour.validAt == Issuance.zulu(day: 13, hour: 0))

    let twentyFourHour = try #require(
      WeatherLoader.bulletin(for: Issuance.zulu(day: 13, hour: 15), in: bulletins)
    )
    #expect(twentyFourHour.validAt == Issuance.zulu(day: 13, hour: 12))
  }

  /// Consecutive use periods share an endpoint; the earlier bulletin wins it.
  @Test
  func selectsTheEarlierBulletinAtASharedBoundary() throws {
    let bulletin = try #require(
      WeatherLoader.bulletin(for: Issuance.zulu(day: 12, hour: 21), in: bulletins)
    )

    #expect(bulletin.validAt == Issuance.zulu(day: 12, hour: 18))
  }

  @Test
  func hasNoBulletinOutsideEveryUsePeriod() {
    #expect(WeatherLoader.bulletin(for: Issuance.zulu(day: 15, hour: 12), in: bulletins) == nil)
    #expect(WeatherLoader.bulletin(for: Issuance.zulu(day: 12, hour: 10), in: bulletins) == nil)
  }
}
