import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A report that has been laid out, ready to leave the app.
///
/// Holding the rendered PDF rather than rendering on demand lets the share sheet preview it: a
/// preview needs a thumbnail up front, and a thumbnail needs the document.
struct SharedReport: Sendable {
  let pdf: Data
  let summary: String
  let documentTitle: String
  let fileName: String

  init(report: Report, pdf: Data) {
    self.pdf = pdf
    summary = report.summary
    documentTitle = report.documentTitle
    fileName = report.fileName
  }
}

extension SharedReport: Transferable {

  /// Offers the report as a PDF first, and as its text summary to anywhere that takes only text.
  ///
  /// The order matters: Files and Mail take the PDF, while Messages and Notes fall through to
  /// the summary — so relaying a number to the other seat no longer means sending a document or
  /// a screenshot.
  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .pdf) { $0.pdf }
      .suggestedFileName { $0.fileName + ".pdf" }

    ProxyRepresentation(exporting: \.summary)
  }
}
