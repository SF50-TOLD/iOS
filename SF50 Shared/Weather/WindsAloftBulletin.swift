import Foundation
import SwiftMETAR

/// Every reporting station’s winds aloft data for a single NWS forecast period.
///
/// The NWS issues one bulletin per forecast period — 6, 12, and 24 hours out — and publishes the
/// period each is to be used for. Together they cover roughly a day from issuance.
struct WindsAloftBulletin: Sendable {

  /// The time the forecast is valid at.
  let validAt: Date

  /// The period the NWS publishes this bulletin for.
  let usePeriod: DateInterval

  /// Wind and temperature data by station identifier.
  let stations: [String: WindsAloftData]

  /// Creates a bulletin from a parsed product, or `nil` if its dates couldn’t be resolved.
  ///
  /// - Parameter product: The parsed winds aloft product from SwiftMETAR.
  init?(from product: WindsAloft) {
    guard let validAt = product.validAt.date,
      let usePeriodStart = product.usePeriod.start.date,
      let usePeriodEnd = product.usePeriod.end.date,
      usePeriodStart <= usePeriodEnd
    else { return nil }

    self.validAt = validAt
    usePeriod = .init(start: usePeriodStart, end: usePeriodEnd)
    stations = product.stations.reduce(into: [:]) { stations, station in
      stations[station.id] = .init(from: station)
    }
  }
}
