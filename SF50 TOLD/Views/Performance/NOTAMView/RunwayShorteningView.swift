import Defaults
import MeasurementKitUI
import SF50_Shared
import SwiftUI

struct RunwayShorteningView: View {
  @Bindable var notam: NOTAM

  /// The runway this NOTAM restricts.
  ///
  /// Passed in rather than reached through the NOTAM: a NOTAM names its runway by identifier, and
  /// a designator the pilot is looking at should come from the runway itself.
  var runway: Runway

  @Environment(\.operation)
  private var operation

  @Default(.runwayLengthUnit)
  private var runwayLengthUnit

  private var runwayName: String {
    runway.name
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
    if let reciprocalName = runway.reciprocal?.name {
      String(localized: "Runway \(reciprocalName) Threshold")
    } else {
      String(
        localized: "Runway \(runwayName) DER",
        comment:
          "The departure end of a runway. “DER” abbreviates “departure end of runway”; the argument is the runway name."
      )
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
          in: runwayLengthUnit,
          format: .length,
          keypad: .whole
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
      RunwayShorteningView(notam: notam, runway: runway)
    }.environment(\.operation, .takeoff)
  }
}
