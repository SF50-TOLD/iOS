import AppKit
import Logging
import SwiftNASR
import SwiftUI

struct NavDataView: View {
  @SwiftUI.State private var viewModel = NavDataProcessorViewModel()
  @SwiftUI.State private var selectedCycleOption: CycleOption = .current
  @SwiftUI.State private var customCycleText = ""

  /// Whether GitHub credentials are configured for upload.
  private var hasGitHubToken: Bool {
    CredentialsConfig[.githubToken] != nil
  }

  private var cycle: Cycle? {
    switch selectedCycleOption {
      case .current: Cycle.effective
      case .next: Cycle.effective.next
      case .custom: stringToCycle(customCycleText)
    }
  }

  var body: some View {
    let showErrorSheet = Binding<Bool>(
      get: { viewModel.uploadError != nil },
      set: { _ in }
    )

    VStack(alignment: .leading) {
      Text("SF50 TOLD Nav Data Downloader")
        .font(.title)
        .fontWeight(.bold)
        .padding(.bottom)

      Form {
        HStack {
          Picker("Cycle", selection: $selectedCycleOption) {
            Text("Current").tag(CycleOption.current)
            Text("Next").tag(CycleOption.next)
            Text("Custom…").tag(CycleOption.custom)
          }
          .disabled(viewModel.isProcessing)

          if selectedCycleOption == .custom {
            TextField("", text: $customCycleText)
              .textFieldStyle(.roundedBorder)
              .help("Enter cycle in format: YYYY-MM-DD (e.g., 2024-01-25)")
              .frame(maxWidth: 100)
              .foregroundStyle(
                isCustomCycleInvalid ? Color.red : Color.primary
              )
          }

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
            Button(buttonTitle, action: downloadAndProcess)
              .buttonStyle(.borderedProminent)
              .controlSize(.large)
              .disabled(cycle == nil)
          }
        }
      }
      if let cycle, let date = cycle.effectiveDate, let endDate = cycle.expirationDate {
        Text(date..<endDate, format: .interval.year().month().day())
          .foregroundStyle(.secondary)
          .font(.caption)
      }

      // Processing UI
      if viewModel.showProgressBar {
        VStack {
          // Progress bar
          ProgressView(value: viewModel.progress) {
            Text(viewModel.statusMessage)
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
        Text(error?.localizedDescription ?? "Unknown error")
        if let failureReason = error?.localizedFailureReason {
          Text(failureReason)
            .font(.caption)
        }

        if let recoverySuggestion = error?.localizedRecoverySuggestion {
          Text(recoverySuggestion)
            .font(.caption)
        }
      }
    }
  }

  // MARK: - Computed Properties

  private var isCustomCycleInvalid: Bool {
    selectedCycleOption == .custom && !customCycleText.isEmpty
      && stringToCycle(customCycleText) == nil
  }

  private var buttonTitle: String {
    hasGitHubToken
      ? String(localized: "Process and Upload")
      : String(localized: "Process and Save")
  }

  private func stringToCycle(_ value: String) -> Cycle? {
    let components = value.split(separator: "-")
    guard components.count == 3 else { return nil }

    guard let year = UInt(components[0]),
      let month = UInt8(components[1]),
      let day = UInt8(components[2])
    else {
      return nil
    }

    return Cycle(year: year, month: month, day: day)
  }

  // MARK: - Actions

  private func downloadAndProcess() {
    // Show file picker to select output directory
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = "Choose a directory to save the processed files:"
    panel.prompt = "Select"

    panel.begin { response in
      guard response == .OK, let url = panel.url, let cycle else {
        return
      }

      // Start processing
      viewModel.process(cycle: cycle, outputURL: url)
    }
  }

  enum CycleOption: CaseIterable {
    case current
    case next
    case custom
  }
}

#Preview {
  NavDataView()
    .frame(width: 600)
    .fixedSize(horizontal: false, vertical: true)
}
