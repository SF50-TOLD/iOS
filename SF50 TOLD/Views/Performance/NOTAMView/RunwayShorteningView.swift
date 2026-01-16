import Defaults
import SF50_Shared
import SwiftUI

struct RunwayShorteningView: View {
  @Bindable var notam: NOTAM

  @Environment(\.operation)
  private var operation

  @Default(.runwayLengthUnit)
  private var runwayLengthUnit

  private var runwayName: String {
    notam.runway.name
  }

  private var shortenPrompt: String {
    switch operation {
      case .takeoff: return String(localized: "Shorten takeoff distance by:")
      case .landing: return String(localized: "Shorten landing distance by:")
    }
  }

  private var shortenBinding: Binding<Measurement<UnitLength>> {
    switch operation {
      case .takeoff: return $notam.takeoffDistanceShortening
      case .landing: return $notam.landingDistanceShortening
    }
  }

  private var locationBinding: Binding<ShorteningLocation> {
    switch operation {
      case .takeoff: return $notam.takeoffShorteningLocation
      case .landing: return $notam.landingShorteningLocation
    }
  }

  private var thresholdLabel: String {
    String(localized: "Runway \(runwayName) Threshold")
  }

  private var DERLabel: String {
    if let reciprocalName = notam.runway.reciprocal?.name {
      String(localized: "Runway \(reciprocalName) Threshold")
    } else {
      String(localized: "Runway \(runwayName) DER")
    }
  }

  var body: some View {
    Section("Runway \(runwayName) Shortening") {
      HStack {
        Text(shortenPrompt)
        Spacer()
        MeasurementField(
          "Distance",
          value: shortenBinding,
          unit: runwayLengthUnit,
          format: .length
        )
        .accessibilityIdentifier("distanceField")
      }

      Picker("Shorten from:", selection: locationBinding) {
        Text(DERLabel).tag(ShorteningLocation.departureEnd)
        Text(thresholdLabel).tag(ShorteningLocation.thresholdEnd)
      }
      .accessibilityIdentifier("shorteningLocationPicker")
    }
  }
}

#Preview {
  PreviewView(insert: .KSQL) { preview in
    let runway = try preview.load(airportID: "SQL", runway: "30")!
    let notam = try preview.addNOTAM(to: runway, shortenTakeoff: 400)

    return List {
      RunwayShorteningView(notam: notam)
    }.environment(\.operation, .takeoff)
  }
}
