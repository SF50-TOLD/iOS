import SF50_Shared
import SwiftUI

/// Row displaying a terrain region with download status.
struct TerrainRegionRow: View {
  let region: TerrainRegion
  let status: TerrainDataLoaderViewModel.RegionDownloadStatus
  let onDownload: () -> Void

  var body: some View {
    LabeledContent(
      content: {
        RegionStatusView(status: status, onDownload: onDownload)
      },
      label: {
        VStack(alignment: .leading) {
          Text(region.displayName)

          Text(Int64(region.sizeBytes), format: .byteCount(style: .file))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    )
  }
}

// MARK: - Previews

#Preview {
  List {
    Section("Available") {
      TerrainRegionRow(
        region: .northAmerica,
        status: .available,
        onDownload: {}
      )
    }

    Section("Not Downloaded") {
      TerrainRegionRow(
        region: .europe,
        status: .notDownloaded,
        onDownload: {}
      )
    }

    Section("Downloading (Indeterminate)") {
      TerrainRegionRow(
        region: .asia,
        status: .downloading(progress: nil),
        onDownload: {}
      )
    }

    Section("Downloading (Progress)") {
      TerrainRegionRow(
        region: .southAmerica,
        status: .downloading(progress: 0.65),
        onDownload: {}
      )
    }
  }
}
