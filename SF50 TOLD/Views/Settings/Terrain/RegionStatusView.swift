import SwiftUI

/// Status indicator for a terrain region download.
struct RegionStatusView: View {
  let status: TerrainDataLoaderViewModel.RegionDownloadStatus
  let onDownload: () -> Void
  let onRedownload: () -> Void

  var body: some View {
    switch status {
      case .available:
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .accessibilityLabel(Text("Downloaded"))

      case .corrupted:
        HStack {
          Text("Corrupted")
          Button("Re-Download") { onRedownload() }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .foregroundStyle(.red)
        .font(.system(size: 14))

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
      RegionStatusView(status: .available, onDownload: {}, onRedownload: {})
    }

    LabeledContent("Corrupted") {
      RegionStatusView(status: .corrupted, onDownload: {}, onRedownload: {})
    }

    LabeledContent("Not Downloaded") {
      RegionStatusView(status: .notDownloaded, onDownload: {}, onRedownload: {})
    }

    LabeledContent("Downloading (Indeterminate)") {
      RegionStatusView(status: .downloading(progress: nil), onDownload: {}, onRedownload: {})
    }

    LabeledContent("Downloading (45%)") {
      RegionStatusView(status: .downloading(progress: 0.45), onDownload: {}, onRedownload: {})
    }
  }
}
