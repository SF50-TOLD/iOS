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
          let status = viewModel.status(for: region)
          TerrainRegionRow(
            region: region,
            status: status,
            onDownload: {
              viewModel.downloadRegion(region)
            },
            onRedownload: {
              viewModel.redownloadRegion(region)
            }
          )
          .swipeActions(edge: .trailing) {
            if status.hasDeletablePayload {
              Button("Delete", role: .destructive) {
                viewModel.deleteRegion(region)
              }
            }
          }
        }
      } footer: {
        Text(
          "iOS can remove downloaded terrain when your device runs low on storage. A region it removed shows as “Removed for space” and can be downloaded again."
        )
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
