import SF50_Shared
import SwiftUI

/// Settings view for managing terrain data downloads.
///
/// Displays a list of available terrain regions with download status
/// and allows users to download additional regions for offline use.
struct TerrainSettingsView: View {
  @StateObject private var viewModel = TerrainDataLoaderViewModel()

  var body: some View {
    List {
      Section {
        ForEach(viewModel.allRegions) { region in
          TerrainRegionRow(
            region: region,
            status: viewModel.status(for: region),
            onDownload: {
              viewModel.downloadRegion(region)
            },
            onRedownload: {
              viewModel.redownloadRegion(region)
            }
          )
        }
      }

      Section {
        LabeledContent("Total Downloaded") {
          Text("\(viewModel.totalDownloadedSize, format: .byteCount(style: .file))")
        }
      }
    }
    .navigationTitle("Terrain Data")
    .withErrorSheet(state: viewModel)
  }
}

#Preview {
  NavigationStack {
    TerrainSettingsView()
  }
}
