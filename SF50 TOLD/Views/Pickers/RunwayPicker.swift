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

  private var runways: [Runway] {
    airport.runways.sorted(using: Runway.NameComparator())
  }

  /// The airport's NOTAMs, resolved in one fetch rather than one per row.
  private var notams: [String: NOTAM] {
    NOTAMStore(context: modelContext).notams(at: airport)
  }

  var body: some View {
    VStack(alignment: .leading) {
      let airportNOTAMs = notams
      List(runways, id: \.name) { runway in
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
