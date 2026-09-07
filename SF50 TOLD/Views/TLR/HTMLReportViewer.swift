import SwiftUI
import WebKit

/// Presents a rendered TLR and offers it for sharing.
struct HTMLReportViewer: View {
  let report: Report
  let reportTitle: String

  @Environment(\.dismiss)
  private var dismiss

  var body: some View {
    NavigationStack {
      HTMLWebView(htmlContent: report.html)
        .navigationTitle(reportTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .navigationBarLeading) {
            Button("Done") {
              dismiss()
            }
          }

          ToolbarItem(placement: .navigationBarTrailing) {
            ShareLink(item: report, preview: SharePreview(report.documentTitle)) {
              Image(systemName: "square.and.arrow.up")
                .accessibilityLabel("Share Report")
            }
          }
        }
    }
  }
}

/// Displays a self-contained HTML document, which carries its own styling inline.
private struct HTMLWebView: UIViewRepresentable {
  let htmlContent: String

  func makeUIView(context _: Context) -> WKWebView {
    WKWebView()
  }

  func updateUIView(_ uiView: WKWebView, context _: Context) {
    uiView.loadHTMLString(htmlContent, baseURL: nil)
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
