import Sentry
import SwiftUI
import WebKit

/// Presents a rendered TLR and offers it for sharing as a PDF.
struct HTMLReportViewer: View {
  let htmlContent: String
  let reportTitle: String

  @Environment(\.dismiss)
  private var dismiss
  @State private var pdfURL: URL?
  @State private var errorMessage: String?
  @State private var showError = false
  @State private var isGeneratingPDF = false

  var body: some View {
    NavigationStack {
      HTMLWebView(htmlContent: htmlContent)
        .navigationTitle(reportTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .navigationBarLeading) {
            Button("Done") {
              dismiss()
            }
          }

          ToolbarItem(placement: .navigationBarTrailing) {
            if let pdfURL {
              ShareLink(item: pdfURL) {
                Image(systemName: "square.and.arrow.up")
                  .accessibilityLabel("Share PDF")
              }
            } else {
              Button(action: generatePDF) {
                Image(systemName: "square.and.arrow.up")
                  .accessibilityLabel("Generate PDF")
              }
              .disabled(isGeneratingPDF)
            }
          }
        }
        .alert("Error", isPresented: $showError) {
          Button("OK", role: .cancel) {}
        } message: {
          if let errorMessage {
            Text(errorMessage)
          }
        }
        .onAppear(perform: generatePDF)
    }
  }

  private func generatePDF() {
    guard !isGeneratingPDF else { return }
    isGeneratingPDF = true
    defer { isGeneratingPDF = false }

    do {
      pdfURL = try writePDF()
    } catch {
      SentrySDK.capture(error: error) { scope in
        scope.setLevel(.warning)
        scope.setFingerprint(["pdf-save"])
      }
      errorMessage = error.localizedDescription
      showError = true
    }
  }

  private func writePDF() throws -> URL {
    let data = try ReportPDF.render(html: htmlContent),
      url = FileManager.default.temporaryDirectory.appendingPathComponent(reportTitle + ".pdf")
    try data.write(to: url)
    return url
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
    htmlContent: "<html><body><h1>Takeoff Report</h1><p>KTST • Runway 36</p></body></html>",
    reportTitle: "Takeoff Report"
  )
}
