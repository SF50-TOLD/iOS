import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A report that has been laid out, ready to leave the app.
///
/// Holding the rendered PDF rather than rendering on demand lets the share sheet preview it: a
/// preview needs a thumbnail up front, and a thumbnail needs the document.
struct SharedReport: Sendable {
  let pdf: Data
  let textReport: String
  let documentTitle: String
  let fileName: String

  init(report: Report, pdf: Data) {
    self.pdf = pdf
    textReport = report.textReport
    documentTitle = report.documentTitle
    fileName = report.fileName
  }
}

extension SharedReport: Transferable {

  /// Offers the report as a PDF first, and as fixed-width text anywhere that takes only text.
  ///
  /// The order matters: Files and Mail take the PDF, while Messages and Notes fall through to
  /// the text — so relaying the numbers no longer means sending a document or a screenshot.
  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .pdf) { $0.pdf }
      .suggestedFileName { $0.fileName + ".pdf" }

    ProxyRepresentation(exporting: \.textReport)
  }
}
