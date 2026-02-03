import SwiftUI

/// Status indicator for a terrain region download.
struct RegionStatusView: View {
  let status: TerrainDataLoaderViewModel.RegionDownloadStatus
  let onDownload: () -> Void

  var body: some View {
    switch status {
      case .available:
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .accessibilityLabel(Text("Downloaded"))

      case .notDownloaded:
        Button("Download") { onDownload() }
          .buttonStyle(.bordered)
          .foregroundStyle(.primary)
          .controlSize(.small)

      case .downloading(let progress):
        if let progress {
          CircularProgressView(progress: .inProgress(progress: progress))
        } else {
          CircularProgressView(progress: .indeterminate)
        }
    }
  }
}

// MARK: - Previews

#Preview {
  List {
    LabeledContent("Available") {
      RegionStatusView(status: .available, onDownload: {})
    }

    LabeledContent("Not Downloaded") {
      RegionStatusView(status: .notDownloaded, onDownload: {})
    }

    LabeledContent("Downloading (Indeterminate)") {
      RegionStatusView(status: .downloading(progress: nil), onDownload: {})
    }

    LabeledContent("Downloading (45%)") {
      RegionStatusView(status: .downloading(progress: 0.45), onDownload: {})
    }
  }
}
