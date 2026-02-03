import AppKit
import SF50_Shared
import SwiftUI
import Logging

/// View for processing SRTM terrain data.
///
/// Processes selected terrain regions with progress tracking. Supports partial processing
/// by allowing users to uncheck regions that already have `.lzma` files in the output directory.
struct TerrainView: View {
  @State private var viewModel: TerrainProcessorViewModel

  /// Whether R2 credentials are configured for upload.
  private var hasR2Credentials: Bool {
    CredentialsConfig[.r2AccountID] != nil && CredentialsConfig[.r2AccessKeyID] != nil
      && CredentialsConfig[.r2SecretAccessKey] != nil
  }

  private var buttonTitle: String {
    hasR2Credentials
      ? String(localized: "Process and Upload")
      : String(localized: "Process and Save")
  }

  var body: some View {
    let showErrorSheet = Binding<Bool>(
      get: { viewModel.uploadError != nil },
      set: { _ in }
    )

    VStack(alignment: .leading) {
      Text("SF50 TOLD Terrain Data Processor")
        .font(.title)
        .fontWeight(.bold)
        .padding(.bottom)

      // Region selection
      RegionSelectionSection(viewModel: viewModel)
        .padding(.bottom)

      // Action buttons
      HStack {
        if viewModel.isProcessing {
          Button(
            viewModel.isCancelling
              ? String(localized: "Stopping…")
              : String(localized: "Stop"),
            action: viewModel.cancel
          )
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .tint(.red)
          .disabled(viewModel.isCancelling)
        } else {
          Button(buttonTitle, action: processAndSave)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.selectedRegions.isEmpty)
        }
      }

      // Processing UI
      if viewModel.showProgressBar {
        VStack {
          ProgressView(value: viewModel.progress) {
            HStack {
              Text(viewModel.statusMessage)
              if let remaining = viewModel.estimatedTimeRemaining() {
                Spacer()
                Text(
                  "\(remaining, format: .units(allowed: [.hours, .minutes], width: .abbreviated, zeroValueUnits: .hide)) remaining"
                )
              }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
          }
          .progressViewStyle(.linear)
        }
      }

      // Log viewer (always visible)
      LogViewer(logEntries: viewModel.logEntries)

      // Error message
      if let errorMessage = viewModel.errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .padding()
          .foregroundStyle(Color.red)
      }
    }
    .padding(30)
    .alert(
      "Upload Error",
      isPresented: showErrorSheet,
      presenting: viewModel.uploadError
    ) { _ in
      Button("OK") {
        viewModel.uploadError = nil
      }
    } message: { error in
      VStack(alignment: .leading) {
        Text(error.localizedDescription)
        if let nsError = error as NSError?,
          let failureReason = nsError.localizedFailureReason
        {
          Text(failureReason)
            .font(.caption)
        }

        if let nsError = error as NSError?,
          let recoverySuggestion = nsError.localizedRecoverySuggestion
        {
          Text(recoverySuggestion)
            .font(.caption)
        }
      }
    }
  }

  init(viewModel: TerrainProcessorViewModel = TerrainProcessorViewModel()) {
    self.viewModel = viewModel
  }

  // MARK: - Actions

  private func processAndSave() {
    // Show file picker to select output directory
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = String(localized: "Choose a directory to save the terrain files:")
    panel.prompt = "Select"

    panel.begin { response in
      guard response == .OK, let url = panel.url else {
        return
      }

      // Start processing all regions (credentials read from xcconfig)
      viewModel.process(outputURL: url)
    }
  }
}

#Preview("Default") {
  TerrainView()
    .frame(width: 600)
    .fixedSize(horizontal: false, vertical: true)
}

#Preview("Processing") {
  let viewModel: TerrainProcessorViewModel = {
    let vm = TerrainProcessorViewModel()
    vm.isProcessing = true
    vm.progress = 0.35
    vm.processingStartDate = Date.now.addingTimeInterval(-120)  // simulate 2 min elapsed at 35%
    vm.statusMessage = "Processing North America: 142 of 4,020"
    vm.logEntries = [
      LogEntry(
        timestamp: Date().addingTimeInterval(-10),
        level: .notice,
        message: "Downloading North America (4,020 tiles)…",
        metadata: nil
      ),
      LogEntry(
        timestamp: Date().addingTimeInterval(-5),
        level: .notice,
        message: "Downloaded 4,020 tiles",
        metadata: nil
      ),
      LogEntry(
        timestamp: Date(),
        level: .warning,
        message: "Tile N35W082.hgt missing, skipping",
        metadata: nil
      )
    ]
    return vm
  }()

  return TerrainView(viewModel: viewModel)
    .frame(width: 600)
    .fixedSize(horizontal: false, vertical: true)
}
