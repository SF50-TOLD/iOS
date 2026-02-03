import SF50_Shared
import SwiftUI

/// Collapsible section for selecting which terrain regions to process.
struct RegionSelectionSection: View {
  @Bindable var viewModel: TerrainProcessorViewModel

  var body: some View {
    DisclosureGroup(
      isExpanded: $viewModel.isRegionSelectionExpanded
    ) {
      VStack(alignment: .leading) {
        // Region checkboxes in a grid
        LazyVGrid(
          columns: [
            GridItem(.flexible(), alignment: .leading),
            GridItem(.flexible(), alignment: .leading)
          ],
          alignment: .leading
        ) {
          ForEach(
            TerrainRegion.allCases.sorted(
              using: SortDescriptor(\.displayName, comparator: .localizedStandard)
            )
          ) { region in
            RegionCheckboxRow(
              region: region,
              isSelected: viewModel.bindingForRegion(region),
              isDisabled: viewModel.isProcessing
            )
          }
        }
      }
      .padding(.top)
    } label: {
      HStack {
        Text("Regions to Process \(Text(regionSelectionLabel).fontWeight(.regular))")
          .font(.headline)

        if viewModel.isRegionSelectionExpanded {
          // Select All / None buttons

          Button("Select All") {
            viewModel.selectAllRegions()
          }
          .controlSize(.small)
          .disabled(viewModel.selectedRegions.count == TerrainRegion.allCases.count)

          Button("Select None") {
            viewModel.selectNoRegions()
          }
          .controlSize(.small)
          .disabled(viewModel.selectedRegions.isEmpty)
        }
      }
    }
    .disabled(viewModel.isProcessing)
  }

  private var regionSelectionLabel: String {
    let selected = viewModel.selectedRegions.count,
      total = TerrainRegion.allCases.count
    return String(
      localized: "(\(selected, format: .number) of \(total, format: .number) selected)",
      comment: "Header for terrain region selection showing count of selected regions"
    )
  }
}

/// Single checkbox row for a terrain region.
struct RegionCheckboxRow: View {
  let region: TerrainRegion
  @Binding var isSelected: Bool
  let isDisabled: Bool

  var body: some View {
    Toggle(isOn: $isSelected) {
      HStack {
        Text("\(region.displayName) (\(Text(region.rawValue).monospaced()))")

        Text("~\(Int64(region.estimatedFileSize), format: .byteCount(style: .file))")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .toggleStyle(.checkbox)
    .disabled(isDisabled)
  }
}

#Preview("Region Selection") {
  RegionSelectionSection(viewModel: TerrainProcessorViewModel())
    .padding()
    .frame(minHeight: 200)
}

#Preview("Checkbox Row") {
  @Previewable @State var selected1 = true
  @Previewable @State var selected2 = false
  @Previewable @State var selected3 = false

  VStack(alignment: .leading, spacing: 8) {
    RegionCheckboxRow(
      region: .northAmerica,
      isSelected: $selected1,
      isDisabled: false
    )

    RegionCheckboxRow(
      region: .europe,
      isSelected: $selected2,
      isDisabled: false
    )

    RegionCheckboxRow(
      region: .asia,
      isSelected: $selected3,
      isDisabled: true
    )
  }
  .padding()
}
