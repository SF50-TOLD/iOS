import Defaults
import SF50_Shared
import Sentry
import SwiftData
import SwiftUI

struct TakeoffReportButton: View {
  @Environment(TakeoffPerformanceViewModel.self)
  private var performance
  @Environment(WeatherViewModel.self)
  private var weather
  @Environment(\.modelContext)
  private var modelContext

  @Environment(ReportPresentation.self)
  private var presentation

  private var container: ModelContainer {
    modelContext.container
  }

  var body: some View {
    Button {
      generateReport()
    } label: {
      HStack {
        if presentation.isGenerating {
          ProgressView()
            .controlSize(.small)
          Text("Generating…")
            .foregroundStyle(.secondary)
        } else {
          Text("Generate Takeoff Report…")
        }
      }
    }
    .accessibilityIdentifier("generateTakeoffReportButton")
    .disabled(!canGenerateReport || presentation.isGenerating)
  }

  private var canGenerateReport: Bool {
    performance.airport != nil && performance.runway != nil
  }

  private func generateReport() {
    guard let airport = performance.airport,
      let runway = performance.runway
    else {
      return
    }

    presentation.isGenerating = true

    Task {
      do {
        // Fetch scenarios using ModelActor in background context
        let fetcher = ScenarioFetcher(modelContainer: container),
          scenarios = try await fetcher.fetchTakeoffScenarios()

        // Allow UI to update with loading state
        try await Task.sleep(nanoseconds: 100_000_000)

        // Capture snapshots and settings on main actor
        let notams = NOTAMStore(context: modelContext).notams(at: airport),
          airportSnapshot = AirportInput(from: airport, notams: notams),
          runwaySnapshot = RunwayInput(from: runway, airport: airport, notam: notams[runway.name]),
          conditions = performance.conditions,
          weight = performance.weight,
          flapSetting = performance.flapSetting,
          safetyFactor = Defaults[.safetyFactorDry],
          useRegressionModel = Defaults[.useRegressionModel],
          aircraft = Defaults.Keys.aircraft,
          emptyWeight = Defaults[.emptyWeight],
          date = weather.time

        // Now run the report generation in the background
        let input = PerformanceInput(
          airport: airportSnapshot,
          runway: runwaySnapshot,
          conditions: conditions,
          weight: weight,
          flapSetting: flapSetting,
          safetyFactor: safetyFactor,
          useRegressionModel: useRegressionModel,
          aircraft: aircraft,
          emptyWeight: emptyWeight,
          date: date
        )
        let generatedReport = try generateTakeoffReport(input: input, scenarios: scenarios)

        await MainActor.run {
          presentation.report = IdentifiableReport(report: generatedReport)
          presentation.isGenerating = false
        }
      } catch {
        SentrySDK.capture(error: error)
        await MainActor.run {
          presentation.error = IdentifiableError(error: error)
          presentation.isGenerating = false
        }
      }
    }
  }
}
