import SF50_Shared
import SwiftUI

/// A generated report, identified so that a sheet can present it.
struct IdentifiableReport: Identifiable {
  let id = UUID()
  let report: Report
}

/// The progress and outcome of a report a pilot asked for: whether it's being generated, and the
/// report or error to show.
///
/// A report button sits in the results pane of ``PerformanceLayout``, which rebuilds that pane when
/// the size class changes. Owning this state, and presenting its sheets, above the layout keeps an
/// open report open across a fold, and lets a report still being generated arrive once it's done.
@Observable
@MainActor
final class ReportPresentation {
  /// Whether a report is being generated.
  var isGenerating = false

  /// The report to show, once one has been generated.
  var report: IdentifiableReport?

  /// The error to show, if generating the report failed.
  var error: IdentifiableError?
}

private struct ReportPresenter: ViewModifier {
  @Bindable var presentation: ReportPresentation
  let reportTitle: String

  func body(content: Content) -> some View {
    content
      .environment(presentation)
      .sheet(item: $presentation.report) { shown in
        HTMLReportViewer(report: shown.report, reportTitle: reportTitle)
      }
      .sheet(item: $presentation.error) { identifiableError in
        ErrorSheet(error: identifiableError.error)
      }
  }
}

extension View {
  /// Presents the reports and errors in `presentation`, and provides it to the report buttons
  /// within.
  ///
  /// - Parameters:
  ///   - presentation: The report state the buttons within update.
  ///   - reportTitle: The title of the report viewer.
  func presentingReports(_ presentation: ReportPresentation, titled reportTitle: String)
    -> some View
  {
    modifier(ReportPresenter(presentation: presentation, reportTitle: reportTitle))
  }
}
