import CoreTransferable
import Foundation
import Sentry
import UniformTypeIdentifiers

extension Report: Transferable {

  /// Offers the report as a PDF first, and as its text summary to anywhere that takes only text.
  ///
  /// The order matters: Files and Mail take the PDF, while Messages and Notes fall through to
  /// the summary — so relaying a number to the other seat no longer means sending a document or
  /// a screenshot.
  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .pdf) { report in
      try await report.pdf()
    }
    .suggestedFileName { $0.fileName + ".pdf" }

    ProxyRepresentation(exporting: \.summary)
  }

  /// Lays the report out as a PDF, reporting a failure before handing it back to the share sheet.
  private func pdf() async throws -> Data {
    do {
      return try await MainActor.run {
        try ReportPDF.render(html: html, documentTitle: documentTitle)
      }
    } catch {
      SentrySDK.capture(error: error) { scope in
        scope.setLevel(.warning)
        scope.setFingerprint(["report-pdf"])
      }
      throw error
    }
  }
}
