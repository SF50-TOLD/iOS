import Foundation
import UIKit

/// Lays a rendered TLR out as a paginated US Letter PDF.
///
/// The report carries its own CSS inline, including the `@media print` rules that expand every
/// what-if scenario, so a markup print formatter can paginate it directly. Nothing here needs a
/// web view, and so nothing here needs to wait for one to load.
enum ReportPDF {

  /// Renders a report's HTML into a paginated US Letter PDF.
  ///
  /// - Parameters:
  ///   - html: The complete HTML document to lay out.
  ///   - documentTitle: The title recorded in the PDF's metadata.
  /// - Returns: The PDF file's contents.
  /// - Throws: ``Errors/emptyReport`` if the report lays out as zero pages.
  @MainActor
  static func render(html: String, documentTitle: String) throws -> Data {
    let renderer = pageRenderer(for: html)
    var pageCount = 0

    // The renderer lays the markup out against the graphics context it will draw into, so its
    // page count is only available from inside one. Asking beforehand never returns.
    let data = UIGraphicsPDFRenderer(
      bounds: renderer.paperRect,
      format: format(titled: documentTitle)
    )
    .pdfData { context in
      pageCount = renderer.numberOfPages
      renderer.prepare(forDrawingPages: .init(location: 0, length: pageCount))
      for page in 0..<pageCount {
        context.beginPage()
        renderer.drawPage(at: page, in: context.pdfContextBounds)
      }
    }

    guard pageCount > 0 else { throw Errors.emptyReport }
    return data
  }

  private static func format(titled documentTitle: String) -> UIGraphicsPDFRendererFormat {
    let format = UIGraphicsPDFRendererFormat()
    format.documentInfo = [kCGPDFContextTitle as String: documentTitle]
    return format
  }

  private static func pageRenderer(for html: String) -> UIPrintPageRenderer {
    let renderer = LetterPageRenderer()
    renderer.addPrintFormatter(UIMarkupTextPrintFormatter(markupText: html), startingAtPageAt: 0)
    return renderer
  }

  /// Failures that can arise while laying a report out as a PDF.
  enum Errors: Error {
    /// The print renderer laid the report out as no pages at all.
    case emptyReport
  }
}

/// A page renderer fixed to US Letter with half-inch margins.
///
/// A print job normally hands `UIPrintPageRenderer` its geometry. Driving one directly leaves
/// both rects empty, and a renderer whose printable area is empty never finishes paginating.
/// They are read-only, and UIKit reads them from its own storage rather than through a subclass
/// override, so key-value coding is what fills them in.
private final class LetterPageRenderer: UIPrintPageRenderer {

  private static let pointsPerInch = 72.0,
    paperSize = CGSize(width: 8.5 * pointsPerInch, height: 11 * pointsPerInch),
    margin = 0.5 * pointsPerInch

  override init() {
    super.init()
    let paper = CGRect(origin: .zero, size: Self.paperSize)
    setValue(paper, forKey: "paperRect")
    setValue(paper.insetBy(dx: Self.margin, dy: Self.margin), forKey: "printableRect")
  }
}
