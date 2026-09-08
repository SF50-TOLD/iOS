import Defaults
import SF50_Shared
import SwiftUI

struct RunwayDistances: View {
  var runway: Runway

  /// The NOTAM restricting this runway, or `nil` if none does.
  var notam: NOTAM?

  @Environment(\.operation)
  private var operation

  var body: some View {
    switch operation {
      case .takeoff:
        if runway.availableTakeoffRun(notamedBy: notam)
          == runway.availableTakeoffDistance(notamedBy: notam)
        {
          RunwayDistance(
            distance: runway.availableTakeoffRun(notamedBy: notam),
            NOTAMed: notam?.shortensTakeoffDistance ?? false
          )
        } else {
          HStack {
            HStack(alignment: .bottom, spacing: 3) {
              RunwayDistance(
                distance: runway.availableTakeoffRun(notamedBy: notam),
                NOTAMed: notam?.shortensTakeoffDistance ?? false
              )
              Text("TORA").font(.caption2).padding(.bottom, 2)
            }
            HStack(alignment: .bottom, spacing: 3) {
              RunwayDistance(
                distance: runway.availableTakeoffDistance(notamedBy: notam),
                NOTAMed: notam?.shortensTakeoffDistance ?? false
              )
              Text("TODA").font(.caption2).padding(.bottom, 2)
            }
          }
        }
      case .landing:
        RunwayDistance(
          distance: runway.availableLandingDistance(notamedBy: notam),
          NOTAMed: notam?.shortensLandingDistance ?? false
        )
    }
  }
}

private struct RunwayDistance: View {
  var distance: Measurement<UnitLength>
  var NOTAMed: Bool

  @Default(.runwayLengthUnit)
  private var runwayLengthUnit

  var body: some View {
    if NOTAMed {
      Text(distance.converted(to: runwayLengthUnit), format: .length)
        .foregroundStyle(Color.ui.warning)
    } else {
      Text(distance.converted(to: runwayLengthUnit), format: .length)
    }
  }
}

#Preview {
  PreviewView(insert: .KOAK) { preview in
    preview.setUpToDate()
    let runway30 = try preview.load(airportID: "OAK", runway: "30")!
    let runway28R = try preview.load(airportID: "OAK", runway: "28R")!
    let runway33 = try preview.load(airportID: "OAK", runway: "33")!
    let runway33NOTAM = try preview.addNOTAM(to: runway33, shortenLanding: 500)

    return List {
      HStack {
        Text("TORA/TODA").foregroundStyle(.secondary)
        Spacer()
        RunwayDistances(runway: runway30, notam: nil)
          .environment(\.operation, .takeoff)
      }

      HStack {
        Text("Length Only").foregroundStyle(.secondary)
        Spacer()
        RunwayDistances(runway: runway28R, notam: nil)
          .environment(\.operation, .takeoff)
      }
      HStack {
        Text("NOTAMed").foregroundStyle(.secondary)
        Spacer()
        RunwayDistances(runway: runway33, notam: runway33NOTAM)
          .environment(\.operation, .landing)
      }
    }
  }
}
