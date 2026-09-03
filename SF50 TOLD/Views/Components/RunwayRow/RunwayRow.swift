import Defaults
import MeasurementKit
import SF50_Shared
import SwiftUI

struct RunwayRow: View {
  var runway: Runway
  var conditions: Conditions
  var flapSetting: FlapSetting?

  @Environment(\.aircraftType)
  private var aircraftType

  @Environment(\.operation)
  private var operation

  @Default(.runwayLengthUnit)
  private var runwayLengthUnit

  @Default(.speedUnit)
  private var speedUnit

  private var limitations: Limitations.Type {
    aircraftType.limitations
  }

  private var crosswindLimit: Measurement<UnitSpeed>? {
    switch flapSetting {
      case .flapsUp, .flapsUpIce, nil: nil
      case .flaps50, .flaps50Ice: limitations.maxCrosswind_flaps50
      case .flaps100: limitations.maxCrosswind_flaps100
    }
  }

  var body: some View {
    HStack {
      Text(runway.name).bold()
      RunwayDistances(runway: runway)
      if runway.isTurf {
        Text("(turf)")
      }

      Spacer()

      WindComponents(
        runway: runway,
        conditions: conditions,
        crosswindLimit: crosswindLimit,
        tailwindLimit: limitations.maxTailwind
      )
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityCustomContent(.contamination, contaminationContent, importance: .high)
    .accessibilityCustomContent(.shortening, shorteningContent, importance: .high)
    .accessibilityCustomContent(.displacedThreshold, displacedThresholdContent, importance: .high)
    .accessibilityCustomContent(.tailwind, tailwindContent, importance: .high)
    .accessibilityCustomContent(.crosswind, crosswindContent, importance: .high)
    .accessibilityCustomContent(.takeoffRunAvailable, takeoffRunContent)
    .accessibilityCustomContent(.takeoffDistanceAvailable, takeoffDistanceContent)
    .accessibilityCustomContent(.landingDistanceAvailable, landingDistanceContent)
    .accessibilityCustomContent(.surface, surfaceContent)
    .accessibilityCustomContent(.slope, slopeContent)
  }
}

// MARK: - Declared distances

extension RunwayRow {
  /// TORA, announced only when it differs from TODA, matching what the row draws.
  fileprivate var takeoffRunContent: Text? {
    guard operation == .takeoff,
      runway.notamedTakeoffRun != runway.notamedTakeoffDistance
    else { return nil }
    return formatted(runway.notamedTakeoffRun)
  }

  fileprivate var takeoffDistanceContent: Text? {
    guard operation == .takeoff else { return nil }
    return formatted(runway.notamedTakeoffDistance)
  }

  fileprivate var landingDistanceContent: Text? {
    guard operation == .landing else { return nil }
    return formatted(runway.notamedLandingDistance)
  }

  private func formatted(_ distance: Measurement<UnitLength>) -> Text {
    Text(distance.converted(to: runwayLengthUnit), format: .length)
  }
}

// MARK: - Surface and slope

extension RunwayRow {
  /// Slopes shallower than this round to nothing at the precision we announce.
  private static var levelSlopeThreshold: Float { 0.0005 }

  /// Only the recorded surface: `Runway.surfaceType` answers "paved" for a runway whose surface
  /// the source data never gave, and announcing that states a fact the row itself never draws.
  fileprivate var surfaceContent: Text? {
    switch runway.recordedSurfaceType {
      case .paved: Text("Paved")
      case .grooved: Text("Grooved")
      case .pfc: Text("Porous friction course")
      case .turf: Text("Turf")
      case nil: nil
    }
  }

  fileprivate var slopeContent: Text? {
    guard let knownGradient else { return nil }
    guard abs(knownGradient) >= Self.levelSlopeThreshold else { return Text("Level") }

    let magnitude = Double(abs(knownGradient))
    return knownGradient > 0
      ? Text("\(magnitude, format: .slope) upslope")
      : Text("\(magnitude, format: .slope) downslope")
  }

  /// The gradient only where one exists to report: `gradientOrBestGuess` answers zero for a
  /// runway that is neither surveyed nor has a reciprocal to estimate from, and announcing that
  /// as level asserts a slope nothing measured.
  private var knownGradient: Float? {
    guard runway.gradient != nil || runway.reciprocal != nil else { return nil }
    return runway.gradientOrBestGuess
  }
}

// MARK: - NOTAM restrictions

extension RunwayRow {
  fileprivate var contaminationContent: Text? {
    switch runway.notam?.contamination {
      case .waterOrSlush(let depth):
        Text("Water/slush \(depth.converted(to: .inches), format: .depth)")
      case .slushOrWetSnow(let depth):
        Text("Slush/wet snow \(depth.converted(to: .inches), format: .depth)")
      case .drySnow: Text("Dry snow")
      case .compactSnow: Text("Compact snow")
      case .wetRunway: Text("Wet runway")
      case .rwyCC(let rwyCC): Text("Runway condition code \(rwyCC, format: .number)")
      case nil: nil
    }
  }

  /// A NOTAMed shortening, described as a reduction rather than a closure: the model has no
  /// closure of its own, and a shortening as long as the runway is the only way it can say so.
  fileprivate var shorteningContent: Text? {
    guard let notam = runway.notam else { return nil }

    let shortening = operationShortening(of: notam)
    guard shortening.value > 0 else { return nil }

    let length = shortening.converted(to: runwayLengthUnit)
    return switch operationShorteningLocation(of: notam) {
      case .thresholdEnd: Text("Shortened \(length, format: .length) at the threshold end")
      case .departureEnd: Text("Shortened \(length, format: .length) at the departure end")
    }
  }

  /// Announced for landing alone: a displaced threshold restricts no takeoff, which runs from the
  /// physical start of the runway.
  fileprivate var displacedThresholdContent: Text? {
    guard operation == .landing,
      let displacedThresholdDistance = runway.displacedThresholdDistance,
      displacedThresholdDistance.value > 0
    else { return nil }
    return formatted(displacedThresholdDistance)
  }

  private func operationShortening(of notam: NOTAM) -> Measurement<UnitLength> {
    switch operation {
      case .takeoff: notam.takeoffDistanceShortening
      case .landing: notam.landingDistanceShortening
    }
  }

  private func operationShorteningLocation(of notam: NOTAM) -> ShorteningLocation {
    switch operation {
      case .takeoff: notam.takeoffShorteningLocation
      case .landing: notam.landingShorteningLocation
    }
  }
}

// MARK: - Wind limits

extension RunwayRow {
  /// The limit exceedance the row otherwise signals with red text alone.
  fileprivate var tailwindContent: Text? {
    let tailwindLimit = limitations.maxTailwind
    guard runway.headwind(conditions: conditions) < -tailwindLimit else { return nil }
    return exceeds(tailwindLimit)
  }

  fileprivate var crosswindContent: Text? {
    guard let crosswindLimit,
      runway.crosswind(conditions: conditions).magnitude > crosswindLimit
    else { return nil }
    return exceeds(crosswindLimit)
  }

  private func exceeds(_ limit: Measurement<UnitSpeed>) -> Text {
    Text("Exceeds \(limit.converted(to: speedUnit), format: .speed) limit")
  }
}

// MARK: - Custom content keys

extension AccessibilityCustomContentKey {
  fileprivate static var contamination: Self { .init("Contamination") }
  fileprivate static var shortening: Self { .init("NOTAM") }
  fileprivate static var displacedThreshold: Self { .init("Displaced threshold") }
  fileprivate static var tailwind: Self { .init("Tailwind") }
  fileprivate static var crosswind: Self { .init("Crosswind") }
  fileprivate static var takeoffRunAvailable: Self { .init("Takeoff run available") }
  fileprivate static var takeoffDistanceAvailable: Self { .init("Takeoff distance available") }
  fileprivate static var landingDistanceAvailable: Self { .init("Landing distance available") }
  fileprivate static var surface: Self { .init("Surface") }
  fileprivate static var slope: Self { .init("Slope") }
}

#Preview("Takeoff") {
  PreviewView(insert: .KSQL, .K1C9) { preview in
    let paved = try preview.load(airportID: "SQL", runway: "30")!
    let turf = try preview.load(airportID: "1C9", runway: "5")!

    return List {
      Section("Paved") {
        RunwayRow(runway: paved, conditions: preview.lightWinds, flapSetting: .flaps100)
      }
      Section("Turf") {
        RunwayRow(runway: turf, conditions: preview.lightWinds, flapSetting: .flaps100)
      }
    }
    .environment(\.operation, .takeoff)
  }
}

#Preview("Landing, NOTAMed") {
  PreviewView(insert: .KSQL) { preview in
    let shortened = try preview.load(airportID: "SQL", runway: "30")!
    try preview.addNOTAM(to: shortened, shortenLanding: 500, contamination: .compactSnow)

    return List {
      RunwayRow(runway: shortened, conditions: preview.strongWinds, flapSetting: .flaps100)
    }
    .environment(\.operation, .landing)
  }
}
