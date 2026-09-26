import SF50_Shared
import Sentry
import SwiftData
import SwiftUI

// periphery:ignore - consumed only by the #Preview macros below
private enum PreviewError: Error {
  case runwayNotFound(String)
}

// periphery:ignore - consumed only by the #Preview macros below
extension NOTAMProposal {
  /// What the parsers read from `NOTAMResponse.readableSamples(baseTime:)` for Oakland runway 30.
  fileprivate static var previewSample: Self {
    var proposal = Self()
    proposal.contamination = [.init(.rwyCC(3), from: .init(notamID: "A9000/26", reader: .parser))]
    proposal.obstacleHeight = [
      .init(.init(value: 170, unit: .feet), from: .init(notamID: "A9001/26", reader: .parser))
    ]
    return proposal
  }
}

// periphery:ignore - consumed only by the #Preview macros below
extension NOTAMView {
  /// The screen just after the pilot filled it in from `notamID`, for previews.
  fileprivate init(
    notam: NOTAM,
    runway: Runway,
    downloadedNOTAMs: [NOTAMResponse],
    proposal: NOTAMProposal,
    filledFrom notamID: String,
    for operation: SF50_Shared.Operation
  ) {
    self.init(
      notam: notam,
      runway: runway,
      downloadedNOTAMs: downloadedNOTAMs,
      plannedTime: .now,
      isLoadingNOTAMs: false,
      proposal: proposal
    )
    let restoration = proposal.from(notamID: notamID).fill(notam, for: operation)
    _fill = State(initialValue: .init(notamIDs: [notamID], restoration: restoration))
  }
}

// MARK: - Filling In

extension NOTAMView {
  private static let bannerID = "fillBanner"

  /// What `downloaded` proposes for the fields this screen edits.
  private func proposal(from downloaded: NOTAMResponse) -> NOTAMProposal? {
    proposal?.from(notamID: downloaded.notamId).fields(for: operation)
  }

  private func canFill(from downloaded: NOTAMResponse) -> Bool {
    proposal(from: downloaded)?.isEmpty == false
  }

  private func fillIn(from downloaded: NOTAMResponse, scrollingWith scroller: ScrollViewProxy) {
    guard let proposal = proposal(from: downloaded) else { return }
    let restoration = proposal.fill(notam, for: operation),
      filledFrom = (fill?.notamIDs ?? []).filter { $0 != downloaded.notamId } + [downloaded.notamId]
    // Undo puts back what the pilot had before the first of these fill-ins.
    withAnimation {
      fill = .init(notamIDs: filledFrom, restoration: fill?.restoration ?? restoration)
    }
    // The banner exists only once this update lands, so it's scrolled to in the next one.
    Task { withAnimation { scroller.scrollTo(Self.bannerID, anchor: .top) } }
  }

  private func undo(_ fill: Fill) {
    fill.restoration.restore(notam)
    withAnimation { self.fill = nil }
  }

  /// A fill-in the pilot hasn't dismissed yet.
  private struct Fill {
    let notamIDs: [String]
    let restoration: NOTAMRestoration
  }
}

struct NOTAMView: View {
  @Bindable var notam: NOTAM

  /// The runway this NOTAM restricts.
  let runway: Runway

  let downloadedNOTAMs: [NOTAMResponse]
  let plannedTime: Date
  let isLoadingNOTAMs: Bool

  /// What the downloaded NOTAMs propose for this runway, once they've been read.
  var proposal: NOTAMProposal?

  /// Whether the downloaded NOTAMs are still being read for what they propose.
  var isReadingNOTAMs = false

  @State private var error: (any Error)?
  @State private var errorSheetPresented = false

  /// The NOTAM the editor was last filled in from, and how to undo it; `nil` once dismissed.
  @State private var fill: Fill?

  /// NOTAMs sorted with intelligent prioritization:
  /// 0. NOTAMs the editor can be filled in from, among those not expired
  /// 1. Currently effective aerodrome NOTAMs
  /// 2. Currently effective non-aerodrome NOTAMs
  /// 3. Future aerodrome NOTAMs (soonest first)
  /// 4. Future non-aerodrome NOTAMs (soonest first)
  /// 5. Expired NOTAMs (most recently expired first)
  private var sortedNOTAMs: [NOTAMResponse] {
    guard !downloadedNOTAMs.isEmpty else { return [] }

    return downloadedNOTAMs.sorted { lhs, rhs in
      // Prioritize by relevance
      let lhsEffectiveWindow = lhs.isEffective(within: plannedTime, windowInterval: 3600)
      let rhsEffectiveWindow = rhs.isEffective(within: plannedTime, windowInterval: 3600)
      let lhsExpired = lhs.hasExpired(before: plannedTime, windowInterval: 3600)
      let rhsExpired = rhs.hasExpired(before: plannedTime, windowInterval: 3600)
      let lhsAerodrome = lhs.isAerodromeRelated
      let rhsAerodrome = rhs.isAerodromeRelated

      // 1. Expired NOTAMs go to the back
      if lhsExpired != rhsExpired {
        return rhsExpired  // Non-expired comes first
      }

      // If both expired, show most recently expired first
      if lhsExpired && rhsExpired {
        if let lhsEnd = lhs.effectiveEnd, let rhsEnd = rhs.effectiveEnd {
          return lhsEnd > rhsEnd
        }
        return false
      }

      // NOTAMs the editor can be filled in from come first
      let lhsFills = canFill(from: lhs), rhsFills = canFill(from: rhs)
      if lhsFills != rhsFills {
        return lhsFills
      }

      // 2. Effective NOTAMs come before future NOTAMs
      if lhsEffectiveWindow != rhsEffectiveWindow {
        return lhsEffectiveWindow
      }

      // 3. Within same effectiveness category, aerodrome NOTAMs come first
      if lhsAerodrome != rhsAerodrome {
        return lhsAerodrome
      }

      // 4. For effective NOTAMs, show newest first (most recently started)
      if lhsEffectiveWindow && rhsEffectiveWindow {
        return lhs.effectiveStart > rhs.effectiveStart
      }

      // 5. For future NOTAMs, show soonest to become effective first
      return lhs.effectiveStart < rhs.effectiveStart
    }
  }

  @Environment(\.operation)
  private var operation

  @Environment(\.presentationMode)
  private var presentationMode

  @Environment(\.modelContext)
  private var modelContext

  var body: some View {
    ScrollViewReader { scroller in
      Form {
        if let fill {
          Section {
            IntelligenceBanner(
              notamIDs: fill.notamIDs,
              onUndo: { undo(fill) },
              onDismiss: { withAnimation { self.fill = nil } }
            )
          }
          .listRowInsets(.init())
          .listRowBackground(Color.clear)
          .id(Self.bannerID)
        }

        RunwayShorteningView(notam: notam, runway: runway)
        if operation == .takeoff { ObstacleView(notam: notam) }
        if operation == .landing {
          ContaminationView(contamination: $notam.contamination)
        }

        Button("Clear NOTAMs") {
          notam.clearFor(operation: operation)
          presentationMode.wrappedValue.dismiss()
        }.accessibilityIdentifier("clearNOTAMsButton")

        if isLoadingNOTAMs {
          Section("Downloading NOTAMs…") {
            HStack {
              Spacer()
              ProgressView()
              Spacer()
            }
            .listRowBackground(Color.clear)
          }
        } else if !downloadedNOTAMs.isEmpty {
          DownloadedNOTAMsSection(
            notams: sortedNOTAMs,
            plannedTime: plannedTime,
            isReading: isReadingNOTAMs,
            canFill: canFill(from:),
            onFill: { fillIn(from: $0, scrollingWith: scroller) }
          )
        }
      }
    }
    .navigationTitle("NOTAMs")
    .onDisappear {
      do {
        try modelContext.save()
      } catch {
        SentrySDK.capture(error: error) { scope in
          scope.setTag(value: "notam", key: "swiftData.entity")
          scope.setFingerprint(["swiftData", "save"])
        }
        self.error = error
        errorSheetPresented = true
      }
    }
    .alert(
      "Couldn’t Save NOTAM",
      isPresented: $errorSheetPresented,
      actions: {
        Button("OK") {
          errorSheetPresented = false
          error = nil
        }
      },
      message: {
        Text(error?.localizedDescription ?? "<no error>")
      }
    )
  }
}

#Preview("Can Fill In, Takeoff") {
  PreviewView(insert: .KOAK) { preview in
    guard let runway = try preview.load(airportID: "OAK", runway: "30") else {
      throw PreviewError.runwayNotFound("OAK/30")
    }
    let notam = try preview.addNOTAM(to: runway)

    return NOTAMView(
      notam: notam,
      runway: runway,
      downloadedNOTAMs: NOTAMResponse.readableSamples() + preview.generateNOTAMs(count: 4),
      plannedTime: .now,
      isLoadingNOTAMs: false,
      proposal: .previewSample
    )
    .environment(\.operation, .takeoff)
  }
}

#Preview("Can Fill In, Landing") {
  PreviewView(insert: .KOAK) { preview in
    guard let runway = try preview.load(airportID: "OAK", runway: "30") else {
      throw PreviewError.runwayNotFound("OAK/30")
    }
    let notam = try preview.addNOTAM(to: runway)

    return NOTAMView(
      notam: notam,
      runway: runway,
      downloadedNOTAMs: NOTAMResponse.readableSamples() + preview.generateNOTAMs(count: 4),
      plannedTime: .now,
      isLoadingNOTAMs: false,
      proposal: .previewSample,
      isReadingNOTAMs: true
    )
    .environment(\.operation, .landing)
  }
}

#Preview("Filled In") {
  PreviewView(insert: .KOAK) { preview in
    guard let runway = try preview.load(airportID: "OAK", runway: "30") else {
      throw PreviewError.runwayNotFound("OAK/30")
    }
    let notam = try preview.addNOTAM(to: runway)

    return NOTAMView(
      notam: notam,
      runway: runway,
      downloadedNOTAMs: NOTAMResponse.readableSamples() + preview.generateNOTAMs(count: 4),
      proposal: .previewSample,
      filledFrom: "A9000/26",
      for: .landing
    )
    .environment(\.operation, .landing)
  }
}

#Preview("Many NOTAMs") {
  PreviewView(insert: .KOAK) { preview in
    guard let runway = try preview.load(airportID: "OAK", runway: "30") else {
      throw PreviewError.runwayNotFound("OAK/30")
    }
    let notam = try preview.addNOTAM(
      to: runway,
      shortenTakeoff: 500.0,
      obstacleHeight: 75,
      obstacleDistance: 0.25
    )

    let sampleNOTAMs = preview.generateNOTAMs(count: 23, baseTime: .now)

    return NOTAMView(
      notam: notam,
      runway: runway,
      downloadedNOTAMs: sampleNOTAMs,
      plannedTime: .now,
      isLoadingNOTAMs: false
    )
    .environment(\.operation, .takeoff)
  }
}

#Preview("Single NOTAM") {
  PreviewView(insert: .KOAK) { preview in
    guard let runway = try preview.load(airportID: "OAK", runway: "30") else {
      throw PreviewError.runwayNotFound("OAK/30")
    }
    let notam = try preview.addNOTAM(
      to: runway,
      shortenTakeoff: 500.0,
      obstacleHeight: 75,
      obstacleDistance: 0.25
    )

    let sampleNOTAMs = preview.generateNOTAMs(count: 1, baseTime: .now)

    return NOTAMView(
      notam: notam,
      runway: runway,
      downloadedNOTAMs: sampleNOTAMs,
      plannedTime: .now,
      isLoadingNOTAMs: false
    )
    .environment(\.operation, .takeoff)
  }
}

#Preview("No NOTAMs") {
  PreviewView(insert: .KOAK) { preview in
    guard let runway = try preview.load(airportID: "OAK", runway: "30") else {
      throw PreviewError.runwayNotFound("OAK/30")
    }
    let notam = try preview.addNOTAM(
      to: runway,
      shortenLanding: 500.0,
      contamination:
        .waterOrSlush(depth: .init(value: 0.2, unit: .inches))
    )

    return NOTAMView(
      notam: notam,
      runway: runway,
      downloadedNOTAMs: [],
      plannedTime: .now,
      isLoadingNOTAMs: false
    )
    .environment(\.operation, .landing)
  }
}

#Preview("Loading") {
  PreviewView(insert: .KOAK) { preview in
    guard let runway = try preview.load(airportID: "OAK", runway: "30") else {
      throw PreviewError.runwayNotFound("OAK/30")
    }
    let notam = try preview.addNOTAM(to: runway)

    return NOTAMView(
      notam: notam,
      runway: runway,
      downloadedNOTAMs: [],
      plannedTime: .now,
      isLoadingNOTAMs: true
    )
    .environment(\.operation, .takeoff)
  }
}
