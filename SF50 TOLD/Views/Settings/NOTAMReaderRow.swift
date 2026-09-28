import SwiftUI

/// Settings row for the on-device NOTAM reader: its size, whether it's here, and Download or Delete.
struct NOTAMReaderRow: View {
  let state: NOTAMModelLoader.State
  let downloadSize: Int?
  let onDownload: () -> Void
  let onDelete: () -> Void

  var body: some View {
    LabeledContent(
      content: { status },
      label: {
        VStack(alignment: .leading) {
          Text("NOTAM Reader")
          if let downloadSize {
            Text(Int64(downloadSize), format: .byteCount(style: .file))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    )
  }

  @ViewBuilder private var status: some View {
    switch state {
      case .absent, .declined, .unavailable(.downloadFailed):
        downloadButton
      case .unavailable(.insufficientSpace):
        HStack {
          Text("Not Enough Space").foregroundStyle(.secondary)
          downloadButton
        }
        .font(.subheadline)
      case .unavailable(.damaged):
        HStack {
          Text("Damaged").foregroundStyle(.red)
          downloadButton
        }
        .font(.subheadline)
      case .unavailable(.notPublished):
        Text("Not Available").foregroundStyle(.secondary)
      case .unavailable(.unloadable):
        Text("Not Supported on This Device").foregroundStyle(.secondary)
      case .downloading(let fraction):
        CircularProgressView(progress: .inProgress(progress: Float(fraction)))
      case .installed, .verifying, .ready:
        Button("Delete", role: .destructive) { onDelete() }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .accessibilityIdentifier("notamReaderDelete")
    }
  }

  private var downloadButton: some View {
    Button("Download") { onDownload() }
      .buttonStyle(.bordered)
      .foregroundStyle(.primary)
      .controlSize(.small)
      .accessibilityIdentifier("notamReaderDownload")
  }
}

// MARK: - Previews

#Preview {
  let states: [(String, NOTAMModelLoader.State)] = [
    ("Not Downloaded", .absent),
    ("Downloading", .downloading(fraction: 0.4)),
    ("Ready", .ready),
    ("Deleted", .declined),
    ("Not Enough Space", .unavailable(.insufficientSpace)),
    ("Damaged", .unavailable(.damaged)),
    ("Not Published", .unavailable(.notPublished))
  ]
  List {
    ForEach(states, id: \.0) { title, state in
      Section(title) {
        NOTAMReaderRow(state: state, downloadSize: 645_000_000, onDownload: {}, onDelete: {})
      }
    }
  }
}
