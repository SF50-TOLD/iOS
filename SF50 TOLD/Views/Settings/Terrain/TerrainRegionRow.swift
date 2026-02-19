import SF50_Shared
import SwiftUI

/// Row displaying a terrain region with download status.
struct TerrainRegionRow: View {
  let region: TerrainRegion
  let status: TerrainDataLoaderViewModel.RegionDownloadStatus
  let onDownload: () -> Void
  let onRedownload: () -> Void

  var body: some View {
    LabeledContent(
      content: {
        RegionStatusView(
          status: status,
          regionCode: region.rawValue,
          onDownload: onDownload,
          onRedownload: onRedownload
        )
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
        onDownload: {},
        onRedownload: {}
      )
    }

    Section("Corrupted") {
      TerrainRegionRow(
        region: .northAmerica,
        status: .corrupted,
        onDownload: {},
        onRedownload: {}
      )
    }

    Section("Not Downloaded") {
      TerrainRegionRow(
        region: .europe,
        status: .notDownloaded,
        onDownload: {},
        onRedownload: {}
      )
    }

    Section("Downloading (Indeterminate)") {
      TerrainRegionRow(
        region: .asia,
        status: .downloading(progress: nil),
        onDownload: {},
        onRedownload: {}
      )
    }

    Section("Downloading (Progress)") {
      TerrainRegionRow(
        region: .southAmerica,
        status: .downloading(progress: 0.65),
        onDownload: {},
        onRedownload: {}
      )
    }
  }
}
