import PDFKit
import Sentry
import SwiftUI
import WebKit

/// Presents a rendered TLR and offers it for sharing.
struct HTMLReportViewer: View {
  let report: Report
  let reportTitle: String

  @Environment(\.dismiss)
  private var dismiss
  @State private var page = WebPage()
  @State private var shared: SharedReport?

  var body: some View {
    NavigationStack {
      WebView(page)
        .navigationTitle(reportTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .navigationBarLeading) {
            Button("Done") {
              dismiss()
            }
          }

          ToolbarItem(placement: .navigationBarTrailing) {
            shareButton
          }
        }
        .task {
          await load()
          layOutForSharing()
        }
    }
  }

  /// Stays in place while the PDF is laid out, so the toolbar does not shift once it appears.
  @ViewBuilder private var shareButton: some View {
    if let shared {
      ShareLink(
        item: shared,
        preview: SharePreview(shared.documentTitle, image: thumbnail(of: shared.pdf))
      ) {
        shareIcon
      }
    } else {
      Button {
      } label: {
        shareIcon
      }
      .disabled(true)
    }
  }

  private var shareIcon: some View {
    Image(systemName: "square.and.arrow.up")
      .accessibilityLabel("Share Report")
  }

  /// Drives the navigation to completion. The report is self-contained, carrying its styling
  /// inline and fetching nothing, so no individual event here is worth acting on — but a failure
  /// would leave a blank sheet, which is worth knowing about.
  private func load() async {
    do {
      for try await _ in page.load(html: report.html) {}
    } catch {
      report(error, as: "report-view")
    }
  }

  /// Lays the report out as a PDF once, so that sharing it costs nothing and the share sheet has
  /// a page to preview.
  private func layOutForSharing() {
    do {
      let pdf = try ReportPDF.render(html: report.html, documentTitle: report.documentTitle)
      shared = .init(report: report, pdf: pdf)
    } catch {
      report(error, as: "report-pdf")
    }
  }

  /// The first page, which the share sheet shows in place of a generic document icon.
  ///
  /// These images are handed to `SharePreview` rather than displayed, and the share sheet reads
  /// the title beside them — so they carry no accessibility label of their own, and cannot: a
  /// label would make them a `View` where an `Image` is required.
  private func thumbnail(of pdf: Data) -> Image {
    guard let firstPage = PDFDocument(data: pdf)?.page(at: 0) else {
      // swiftlint:disable:next accessibility_label_for_image
      return Image(systemName: "doc.richtext")
    }
    let bounds = firstPage.bounds(for: .mediaBox)
    // swiftlint:disable:next accessibility_label_for_image
    return Image(uiImage: firstPage.thumbnail(of: bounds.size, for: .mediaBox))
  }

  private func report(_ error: any Error, as fingerprint: String) {
    SentrySDK.capture(error: error) { scope in
      scope.setLevel(.warning)
      scope.setFingerprint([fingerprint])
    }
  }
}

#Preview {
  HTMLReportViewer(
    report: .init(
      html: "<html><body><h1>Takeoff Report</h1><p>KTST • Runway 36</p></body></html>",
      documentTitle: "Takeoff Report KTST Rwy 36 Sep 7 at 7:08 PM GMT",
      summary: "Takeoff Report KTST Rwy 36\nGround run 1,803 ft (+3,197 ft)"
    ),
    reportTitle: "Takeoff Report"
  )
}
