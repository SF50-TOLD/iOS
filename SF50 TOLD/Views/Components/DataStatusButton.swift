import SF50_Shared
import SwiftData
import SwiftUI

/// Reports whether the weather and navigation data behind a profile is current and complete.
struct DataStatusButton: View {
  let terrainDataAvailable: Bool
  let terrainDataCorrupted: Bool
  let obstacleDataAvailable: Bool
  let windsAloft: Loadable<WindsAloftForecast?>
  let timeZone: TimeZone

  @Query private var cycles: [Cycle]
  @State private var showingSheet: Bool

  private var cifpCycle: Cycle? {
    cycles.first { $0.dataSource == .cifp }
  }

  private var dofCycle: Cycle? {
    cycles.first { $0.dataSource == .dof }
  }

  private var hasWindsAloft: Bool {
    guard case .value(let forecast) = windsAloft else { return false }
    return forecast != nil
  }

  private var hasIssue: Bool {
    cifpCycle?.isEffective != true
      || dofCycle?.isEffective != true
      || !terrainDataAvailable
      || !obstacleDataAvailable
      || !hasWindsAloft
  }

  var body: some View {
    Button {
      showingSheet = true
    } label: {
      Image(
        systemName: hasIssue
          ? "exclamationmark.triangle.fill"
          : "checkmark.circle"
      )
      .foregroundStyle(hasIssue ? .yellow : .gray)
      .accessibilityLabel(
        hasIssue
          ? String(localized: "Incomplete data") : String(localized: "Up-to-date data")
      )
      .contentTransition(.symbolEffect)
      .animation(.snappy, value: hasIssue)
    }
    .sheet(isPresented: $showingSheet) {
      NavigationStack {
        List {
          Section("Weather Data") {
            ForecastStatusRow(
              label: String(localized: "NWS Winds Aloft"),
              forecast: windsAloft,
              timeZone: timeZone
            )
          }
          Section("Navigation Data") {
            ExpiringStatusRow(label: String(localized: "FAA CIFP Effectivity"), cycle: cifpCycle)
            ExpiringStatusRow(label: String(localized: "FAA DOF Effectivity"), cycle: dofCycle)
            PresenceStatusRow(
              label: String(localized: "FAA DOF Coverage"),
              status: obstacleDataAvailable ? .available : .unavailable
            )
            PresenceStatusRow(
              label: String(localized: "SRTM Terrain Coverage"),
              status: terrainDataCorrupted
                ? .corrupted
                : terrainDataAvailable ? .available : .unavailable
            )
          }
        }
        .navigationTitle("Data Status")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { showingSheet = false }
          }
        }
      }
      .presentationDetents([.medium])
    }
  }

  init(
    terrainDataAvailable: Bool,
    terrainDataCorrupted: Bool = false,
    obstacleDataAvailable: Bool,
    windsAloft: Loadable<WindsAloftForecast?> = .notLoaded,
    timeZone: TimeZone = .gmt,
    showingSheet: Bool = false
  ) {
    self.terrainDataAvailable = terrainDataAvailable
    self.terrainDataCorrupted = terrainDataCorrupted
    self.obstacleDataAvailable = obstacleDataAvailable
    self.windsAloft = windsAloft
    self.timeZone = timeZone
    self._showingSheet = State(initialValue: showingSheet)
  }

  // MARK: - Subtypes

  private struct ExpiringStatusRow: View {
    let label: String
    let cycle: (any AnyCycle)?

    private var notLoaded: Bool { cycle == nil }
    private var isEffective: Bool { cycle?.isEffective == true }

    var body: some View {
      LabeledContent(label) {
        HStack {
          if notLoaded {
            Text("Not Loaded")
            Image(systemName: "questionmark.circle.fill")
              .accessibilityHidden(true)
          } else if isEffective {
            Text("Up to Date")
            Image(systemName: "checkmark.circle.fill")
              .accessibilityHidden(true)
          } else {
            Text("Out of Date")
            Image(systemName: "xmark.circle.fill")
              .accessibilityHidden(true)
          }
        }
      }
    }
  }

  /// Reports a forecast that applies to a period of time, rather than to a coverage area or a
  /// cycle.
  ///
  /// A forecast covering the planned time is simply valid; the period it covers is a detail the
  /// pilot can disclose, and too long to spell out in the row itself. Most airports are not
  /// themselves forecast locations, so the row distinguishes a forecast interpolated between
  /// nearby stations from one reported for the airport, and a bulletin that failed to download —
  /// which a retry may well fix — from a time and place nothing is published for.
  private struct ForecastStatusRow: View {
    let label: String
    let forecast: Loadable<WindsAloftForecast?>
    let timeZone: TimeZone

    /// Formatted here rather than interpolated into `Text`, which resolves a format style
    /// against the environment’s time zone instead of the one the style carries.
    private var timeStyle: Date.FormatStyle {
      var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
      style.timeZone = timeZone
      return style
    }

    private var periodStyle: Date.IntervalFormatStyle {
      var style = Date.IntervalFormatStyle(date: .abbreviated, time: .shortened)
      style.timeZone = timeZone
      return style
    }

    var body: some View {
      switch forecast {
        case .value(let forecast?):
          DisclosureGroup {
            LabeledContent("Valid At") {
              Text(forecast.validAt.formatted(timeStyle))
            }
            LabeledContent("For Use") {
              Text((forecast.usePeriod.start..<forecast.usePeriod.end).formatted(periodStyle))
            }
          } label: {
            summary(
              forecast.isInterpolated
                ? String(localized: "Interpolated") : String(localized: "Valid"),
              systemImage: "checkmark.circle.fill"
            )
          }
        case .error:
          summary(
            String(localized: "Download Failed"),
            systemImage: "exclamationmark.triangle.fill"
          )
        case .value, .loading, .notLoaded:
          summary(String(localized: "Invalid"), systemImage: "xmark.circle.fill")
      }
    }

    private func summary(_ status: String, systemImage: String) -> some View {
      LabeledContent(label) {
        HStack {
          Text(status)
          Image(systemName: systemImage)
            .accessibilityHidden(true)
        }
      }
    }
  }

  private struct PresenceStatusRow: View {
    let label: String
    let status: DataStatus

    var body: some View {
      LabeledContent(label) {
        HStack {
          switch status {
            case .available:
              Text("Available")
              Image(systemName: "checkmark.circle.fill")
                .accessibilityHidden(true)
            case .corrupted:
              Text("Corrupted")
                .foregroundStyle(.red)
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            case .unavailable:
              Text("Not Available")
              Image(systemName: "xmark.circle.fill")
                .accessibilityHidden(true)
          }
        }
      }
    }
  }

  enum DataStatus {
    case available
    case corrupted
    case unavailable
  }
}

#Preview("All Good") {
  PreviewView { helper in
    helper.insertCurrentCycle(.cifp, name: "AIRAC 2601")
    helper.insertCurrentCycle(.dof, name: "20260101")
    return NavigationStack {
      Text("Climb Profile")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            DataStatusButton(
              terrainDataAvailable: true,
              obstacleDataAvailable: true,
              windsAloft: .value(.preview)
            )
          }
        }
    }
  }
}

#Preview("Has Issues") {
  PreviewView { helper in
    helper.insertExpiredCycle(.cifp, name: "AIRAC 2513")
    helper.insertCurrentCycle(.dof, name: "20260101")
    return NavigationStack {
      Text("Climb Profile")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            DataStatusButton(
              terrainDataAvailable: false,
              obstacleDataAvailable: true
            )
          }
        }
    }
  }
}

#Preview("Terrain Corrupted") {
  PreviewView { helper in
    helper.insertCurrentCycle(.cifp, name: "AIRAC 2601")
    helper.insertCurrentCycle(.dof, name: "20260101")
    return NavigationStack {
      Text("Climb Profile")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            DataStatusButton(
              terrainDataAvailable: false,
              terrainDataCorrupted: true,
              obstacleDataAvailable: true,
              windsAloft: .value(.preview),
              showingSheet: true
            )
          }
        }
    }
  }
}

#Preview("Winds Aloft Interpolated") {
  PreviewView { helper in
    helper.insertCurrentCycle(.cifp, name: "AIRAC 2601")
    helper.insertCurrentCycle(.dof, name: "20260101")
    return NavigationStack {
      Text("Climb Profile")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            DataStatusButton(
              terrainDataAvailable: true,
              obstacleDataAvailable: true,
              windsAloft: .value(.previewInterpolated),
              showingSheet: true
            )
          }
        }
    }
  }
}

#Preview("Winds Aloft Unavailable") {
  PreviewView { helper in
    helper.insertCurrentCycle(.cifp, name: "AIRAC 2601")
    helper.insertCurrentCycle(.dof, name: "20260101")
    return NavigationStack {
      Text("Climb Profile")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            DataStatusButton(
              terrainDataAvailable: true,
              obstacleDataAvailable: true,
              windsAloft: .value(nil),
              showingSheet: true
            )
          }
        }
    }
  }
}

#Preview("Winds Aloft Download Failed") {
  PreviewView { helper in
    helper.insertCurrentCycle(.cifp, name: "AIRAC 2601")
    helper.insertCurrentCycle(.dof, name: "20260101")
    return NavigationStack {
      Text("Climb Profile")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            DataStatusButton(
              terrainDataAvailable: true,
              obstacleDataAvailable: true,
              windsAloft: .error(URLError(.timedOut)),
              showingSheet: true
            )
          }
        }
    }
  }
}
