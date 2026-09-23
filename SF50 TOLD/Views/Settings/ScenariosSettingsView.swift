import Sentry
import SF50_Shared
import SwiftData
import SwiftUI

struct ScenariosSettingsView: View {
  @Environment(\.modelContext)
  private var modelContext

  @Query(
    sort: [SortDescriptor(\Scenario._operation), SortDescriptor(\Scenario.name)],
    sectionBy: \._operation
  )
  private var scenarios: SectionedResults<Scenario, String>

  @State private var errorState = ErrorState()

  var body: some View {
    Form {
      ScenarioSection(
        title: "Takeoff Scenarios",
        operation: .takeoff,
        scenarios: scenarios(for: .takeoff)
      )
      ScenarioSection(
        title: "Landing Scenarios",
        operation: .landing,
        scenarios: scenarios(for: .landing)
      )

      if scenarios.isEmpty {
        Section {
          Button("Restore Default Scenarios") { restoreDefaultScenarios() }
        }
      }
    }
    .navigationTitle("Scenarios")
    .withErrorSheet(state: errorState)
  }

  private func scenarios(for operation: SF50_Shared.Operation) -> [Scenario] {
    scenarios[sectionTitle: operation.rawValue].map(Array.init) ?? []
  }

  private func restoreDefaultScenarios() {
    withAnimation {
      for scenario in Scenario.defaultScenarios() {
        modelContext.insert(scenario)
      }

      do {
        try modelContext.save()
      } catch {
        SentrySDK.capture(error: error) { scope in
          scope.setTag(value: "scenario", key: "swiftData.entity")
          scope.setFingerprint(["swiftData", "save"])
        }
        errorState.error = error
      }
    }
  }
}

private struct ScenarioSection: View {
  @Environment(\.modelContext)
  private var modelContext

  let title: LocalizedStringKey
  let operation: SF50_Shared.Operation
  let scenarios: [Scenario]

  var body: some View {
    Section(title) {
      ForEach(scenarios) { scenario in
        NavigationLink(destination: ScenarioDetailView(scenario: scenario)) {
          Text(scenario.name)
        }
      }
      .onDelete { indices in
        for index in indices { modelContext.delete(scenarios[index]) }
      }

      NavigationLink(destination: NewScenarioView(operation: operation)) {
        Label("Add Scenario", systemImage: "plus.circle.fill")
      }
    }
  }
}

private struct NewScenarioView: View {
  @Environment(\.modelContext)
  private var modelContext

  let operation: SF50_Shared.Operation

  @State private var scenario: Scenario?

  var body: some View {
    Group {
      if let scenario {
        ScenarioDetailView(scenario: scenario)
      } else {
        ProgressView()
          .onAppear {
            createScenario()
          }
      }
    }
  }

  private func createScenario() {
    let newScenario = Scenario(name: "New Scenario", operation: operation)
    modelContext.insert(newScenario)
    try? modelContext.save()
    scenario = newScenario
  }
}

@MainActor
@Observable
private final class ErrorState: WithIdentifiableError {
  var error: (any Error)?
}

#Preview("With Scenarios") {
  PreviewView { helper in
    try helper.insertBasicScenarios()

    return NavigationStack {
      ScenariosSettingsView()
    }
  }
}

#Preview("No Scenarios") {
  PreviewView { _ in
    NavigationStack {
      ScenariosSettingsView()
    }
  }
}
