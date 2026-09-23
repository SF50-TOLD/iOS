import Foundation
import Testing

@testable import SF50_TOLD

/// The background refresh spends a pilot's data and replaces their dataset unattended, so when it
/// may run is the decision worth pinning down: never before the pilot has chosen to load anything,
/// straight away once what they have is out of date, and otherwise not until it lapses.
struct `Nav Data Refresh Plan` {
  private static let expiry = Date(timeIntervalSinceReferenceDate: 800_000_000)

  private static func state(
    noData: Bool = false,
    needsLoad: Bool = false,
    nasrCycleExpires: Date? = expiry
  ) -> NavDataStateHelper.State {
    .init(
      noData: noData,
      needsLoad: needsLoad,
      canSkip: !noData,
      nasrCycleExpires: nasrCycleExpires
    )
  }

  @Test
  func `leaves the first load to the pilot`() {
    #expect(NavDataRefreshPlan(Self.state(noData: true, needsLoad: true)) == .none)
  }

  @Test
  func `waits for a current cycle to expire`() {
    #expect(NavDataRefreshPlan(Self.state()) == .at(Self.expiry))
  }

  @Test
  func `refreshes a lapsed dataset straight away`() {
    #expect(NavDataRefreshPlan(Self.state(needsLoad: true)) == .now)
  }

  @Test
  func `refreshes a dataset with no cycle straight away`() {
    #expect(NavDataRefreshPlan(Self.state(needsLoad: true, nasrCycleExpires: nil)) == .now)
  }
}
