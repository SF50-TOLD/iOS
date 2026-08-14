import Foundation
import SwiftMETAR

/// Every reporting station’s winds aloft data for a single NWS forecast period.
///
/// The NWS issues one bulletin per forecast period — 6, 12, and 24 hours out — and publishes the
/// period each is to be used for. Together they cover roughly a day from issuance. Each period is
/// published separately for each region; ``merged(_:)`` folds those back into one bulletin per
/// period.
struct WindsAloftBulletin: Sendable {

  /// The time the forecast is valid at.
  let validAt: Date

  /// The period the NWS publishes this bulletin for.
  let usePeriod: DateInterval

  /// Wind and temperature data by station identifier.
  let stations: [String: WindsAloftData]

  init(validAt: Date, usePeriod: DateInterval, stations: [String: WindsAloftData]) {
    self.validAt = validAt
    self.usePeriod = usePeriod
    self.stations = stations
  }

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

  /// Combines the regional bulletins covering the same period into one bulletin per period.
  ///
  /// Every region publishes the same valid time and use period for a given forecast hour, and the
  /// regions report disjoint sets of stations, so this is a lossless union. Bulletins are grouped
  /// by the period they are published for rather than assumed to agree: a region that ever
  /// diverged would yield its own bulletin instead of being merged into a period it doesn’t belong
  /// to.
  ///
  /// - Parameter bulletins: The loaded bulletins, in any order.
  /// - Returns: One bulletin per distinct use period, ordered by valid time.
  static func merged(_ bulletins: [Self]) -> [Self] {
    Dictionary(grouping: bulletins, by: \.usePeriod)
      .values
      .compactMap { group in
        guard let first = group.first else { return nil }
        let stations = group.reduce(into: [String: WindsAloftData]()) { stations, bulletin in
          stations.merge(bulletin.stations) { existing, _ in existing }
        }
        return .init(validAt: first.validAt, usePeriod: first.usePeriod, stations: stations)
      }
      .sorted { $0.validAt < $1.validAt }
  }
}
