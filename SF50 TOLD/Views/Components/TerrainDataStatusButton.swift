import SF50_Shared
import SwiftData
import SwiftUI

struct TerrainDataStatusButton: View {
  let terrainDataAvailable: Bool
  let obstacleDataAvailable: Bool

  @Query private var cycles: [Cycle]
  @State private var showingSheet: Bool

  private var cifpCycle: Cycle? {
    cycles.first { $0.dataSource == .cifp }
  }

  private var dofCycle: Cycle? {
    cycles.first { $0.dataSource == .dof }
  }

  private var hasIssue: Bool {
    cifpCycle?.isEffective != true
      || dofCycle?.isEffective != true
      || !terrainDataAvailable
      || !obstacleDataAvailable
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
    }
    .sheet(isPresented: $showingSheet) {
      NavigationStack {
        List {
          ExpiringStatusRow(label: String(localized: "FAA CIFP Effectivity"), cycle: cifpCycle)
          ExpiringStatusRow(label: String(localized: "FAA DOF Effectivity"), cycle: dofCycle)
          PresenceStatusRow(
            label: String(localized: "FAA DOF Coverage"),
            isAvailable: obstacleDataAvailable
          )
          PresenceStatusRow(
            label: String(localized: "SRTM Terrain Coverage"),
            isAvailable: terrainDataAvailable
          )
        }
        .navigationTitle("Navigation Data")
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
    obstacleDataAvailable: Bool,
    showingSheet: Bool = false
  ) {
    self.terrainDataAvailable = terrainDataAvailable
    self.obstacleDataAvailable = obstacleDataAvailable
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

  private struct PresenceStatusRow: View {
    let label: String
    let isAvailable: Bool

    var body: some View {
      LabeledContent(label) {
        HStack {
          if isAvailable {
            Text("Available")
            Image(systemName: "checkmark.circle.fill")
              .accessibilityHidden(true)
          } else {
            Text("Not Available")
            Image(systemName: "xmark.circle.fill")
              .accessibilityHidden(true)
          }
        }
      }
    }
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
            TerrainDataStatusButton(
              terrainDataAvailable: true,
              obstacleDataAvailable: true
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
            TerrainDataStatusButton(
              terrainDataAvailable: false,
              obstacleDataAvailable: true
            )
          }
        }
    }
  }
}
