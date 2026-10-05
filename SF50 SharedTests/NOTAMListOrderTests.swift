import Foundation
import Testing

@testable import SF50_Shared

struct `Downloaded-NOTAM list order` {
  private static let plannedTime = Date(timeIntervalSince1970: 1_800_000_000),
    hour: TimeInterval = 3600

  /// A NOTAM starting `startHours` from the planned time and ending `endHours` from it, if ever.
  private static func notam(
    _ id: String,
    startHours: Double,
    endHours: Double? = nil,
    isAerodrome: Bool = true,
    isRelevant: Bool = false
  ) -> NOTAMResponse {
    var notam = NOTAMResponse(
      id: 0,
      notamId: id,
      icaoLocation: "KOAK",
      effectiveStart: plannedTime.addingTimeInterval(startHours * hour),
      effectiveEnd: endHours.map { plannedTime.addingTimeInterval($0 * hour) },
      schedule: nil,
      notamText: id,
      qLine: nil,
      purpose: nil,
      scope: isAerodrome ? "A" : "E",
      trafficType: nil
    )
    notam.isRelevant = isRelevant
    return notam
  }

  @Test
  func `puts fillable, then relevant, then other NOTAMs first, and expired ones last`() {
    let notams = [
      Self.notam("expired long ago", startHours: -48, endHours: -24, isRelevant: true),
      Self.notam("other, future", startHours: 12),
      Self.notam("relevant, future", startHours: 6, isRelevant: true),
      Self.notam("other, effective, en route", startHours: -1, isAerodrome: false),
      Self.notam("fillable, future", startHours: 24, isRelevant: true),
      Self.notam("expired recently", startHours: -48, endHours: -3),
      Self.notam("other, effective, older", startHours: -10),
      Self.notam("relevant, effective", startHours: -2, isRelevant: true),
      Self.notam("fillable, effective", startHours: -5),
      Self.notam("other, effective, newer", startHours: -2),
      Self.notam("relevant, sooner", startHours: 3, isRelevant: true)
    ]

    let order = notams.sortedForList(at: Self.plannedTime) { $0.notamId.hasPrefix("fillable") }

    #expect(
      order.map(\.notamId) == [
        "fillable, effective",
        "fillable, future",
        "relevant, effective",
        "relevant, sooner",
        "relevant, future",
        "other, effective, newer",
        "other, effective, older",
        "other, effective, en route",
        "other, future",
        "expired recently",
        "expired long ago"
      ]
    )
  }
}
