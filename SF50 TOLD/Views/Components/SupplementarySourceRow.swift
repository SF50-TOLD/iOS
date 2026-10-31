import NavData
import SF50_Shared
import SwiftUI

/// A data source beyond the FAA's: what its name stands for, the edition the installed dataset
/// carries, and, where the source asks apps to offer one, a way to report errors in its data.
struct SupplementarySourceRow: View {
  let source: AirportDataCodable.SupplementarySource

  /// What the source's name stands for, or the dataset's own credit line for a source this build
  /// doesn't know.
  private var caption: Text {
    switch source.name {
      case "LFV": Text("Luftfartsverket (Sweden)")
      case "NATS": Text("National Air Traffic Services (UK)")
      case "FOCA": Text("Federal Office of Civil Aviation (Switzerland)")
      case "Austro Control": Text("Air navigation service provider (Austria)")
      case "open flightmaps": Text("Community-maintained aeronautical database")
      default: Text(source.attribution)
    }
  }

  var body: some View {
    VStack(alignment: .leading) {
      CaptionedRow(title: Text(source.name), caption: caption) {
        Text(source.edition)
          .bold()
          .foregroundStyle(.primary)
      }
      if let feedbackURL = source.feedbackURL {
        DataErrorReportLink(sourceName: source.name, destination: feedbackURL)
      }
    }
  }
}

/// Opens the page where a data source takes reports of errors in its data.
struct DataErrorReportLink: View {
  let sourceName: String
  let destination: URL

  var body: some View {
    Link(
      "Report a Data Error to \(sourceName)",
      destination: destination
    )
    .font(.callout)
  }
}

#Preview {
  List {
    ForEach(PreviewHelper.supplementarySources, id: \.name) { source in
      SupplementarySourceRow(source: source)
    }
  }
}
