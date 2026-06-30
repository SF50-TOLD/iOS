import SwiftUI

/// Status indicator for a terrain region download.
struct RegionStatusView: View {
  let status: TerrainDataLoaderViewModel.RegionDownloadStatus
  let regionCode: String
  let onDownload: () -> Void
  let onRedownload: () -> Void

  var body: some View {
    switch status {
      case .available:
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .accessibilityLabel(Text("Downloaded"))
          .accessibilityIdentifier("terrainDownloaded-\(regionCode)")

      case .corrupted:
        HStack {
          Text("Corrupted")
          Button("Re-Download") { onRedownload() }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .foregroundStyle(.red)
        .font(.subheadline)

      case .notDownloaded:
        Button("Download") { onDownload() }
          .buttonStyle(.bordered)
          .foregroundStyle(.primary)
          .controlSize(.small)
          .accessibilityIdentifier("terrainDownload-\(regionCode)")

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
      RegionStatusView(status: .available, regionCode: "na", onDownload: {}, onRedownload: {})
    }

    LabeledContent("Corrupted") {
      RegionStatusView(status: .corrupted, regionCode: "na", onDownload: {}, onRedownload: {})
    }

    LabeledContent("Not Downloaded") {
      RegionStatusView(status: .notDownloaded, regionCode: "eu", onDownload: {}, onRedownload: {})
    }

    LabeledContent("Downloading (Indeterminate)") {
      RegionStatusView(
        status: .downloading(progress: nil),
        regionCode: "as",
        onDownload: {},
        onRedownload: {}
      )
    }

    LabeledContent("Downloading (45%)") {
      RegionStatusView(
        status: .downloading(progress: 0.45),
        regionCode: "sa",
        onDownload: {},
        onRedownload: {}
      )
    }
  }
}
