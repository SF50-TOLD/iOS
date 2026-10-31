import Defaults
import NavData
import SF50_Shared
import SwiftData
import SwiftUI

struct RunwayPicker: View {
  var airport: Airport
  var conditions: Conditions
  var crosswindLimit: Measurement<UnitSpeed>?
  var tailwindLimit: Measurement<UnitSpeed>?
  var onSelect: (Runway) -> Void

  @Environment(\.presentationMode)
  private var mode

  @Environment(\.modelContext)
  private var modelContext

  @Default(.supplementarySources)
  private var supplementarySources

  private var runways: [Runway] {
    airport.runways.sorted(using: Runway.NameComparator())
  }

  /// The sources behind this airport's data that take reports of errors in it.
  private var reportableSources: [AirportDataCodable.SupplementarySource] {
    supplementarySources.filter { source in
      source.feedbackURL != nil && source.source.map(airport.sources.contains) == true
    }
  }

  /// The airport's NOTAMs, resolved in one fetch rather than one per row.
  private var notams: [String: NOTAM] {
    NOTAMStore(context: modelContext).notams(at: airport)
  }

  var body: some View {
    VStack(alignment: .leading) {
      let airportNOTAMs = notams
      List {
        ForEach(runways, id: \.name) { runway in
          RunwayRow(
            runway: runway,
            notam: airportNOTAMs[runway.name],
            conditions: conditions
          )
          .onTapGesture {
            onSelect(runway)
            mode.wrappedValue.dismiss()
          }
          .accessibility(addTraits: .isButton)
          .accessibilityIdentifier("runwayRow-\(runway.name)")
        }

        if !reportableSources.isEmpty {
          Section {
            ForEach(reportableSources, id: \.name) { source in
              if let feedbackURL = source.feedbackURL {
                DataErrorReportLink(sourceName: source.name, destination: feedbackURL)
              }
            }
          }
        }
      }
    }
    .navigationTitle("Runway")
  }
}

#Preview {
  PreviewView(insert: .KOAK) { preview in
    let OAK = try preview.load(locationID: "OAK")!

    return RunwayPicker(
      airport: OAK,
      conditions: preview.lightWinds
    ) { _ in }
    .environment(\.operation, .takeoff)
  }
}
