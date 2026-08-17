import SF50_Shared
import SwiftUI

/// The weather field drawn behind a climb profile.
///
/// One field at a time: the layers all colour the same area, so a second would hide the first. Wind
/// is not among them — it is drawn as barbs over whichever field is showing, and toggled separately.
enum WeatherProfileLayer: String, CaseIterable, Identifiable {
  case none, temperature, clouds, icing

  var id: String { rawValue }

  /// What the picker calls this layer.
  var label: String {
    switch self {
      case .none: String(localized: "None")
      case .temperature: String(localized: "Temperature")
      case .clouds: String(localized: "Clouds")
      case .icing: String(localized: "Icing")
    }
  }

  /// Whether this layer is drawn from a downloaded atmospheric profile.
  var needsAtmosphere: Bool { self != .none }
}

extension AtmosphericProfile.Level {

  /// The temperature band icing is graded across, in °C.
  ///
  /// Water does not freeze onto the airframe at or above the warm limit, and below the cold limit
  /// cloud is largely ice crystals already. In between, interest peaks across the band where
  /// supercooled water is most often found. The limits follow the FAA/NCAR icing products, which
  /// take icing as unusual colder than −25 °C.
  private static let icingWarmLimitC = 0.0,
    icingPeakWarmC = -2.0,
    icingPeakColdC = -15.0,
    icingColdLimitC = -25.0

  /// The humidity ramp, as a fraction of saturation.
  ///
  /// Humidity stands in for visible moisture, since a model reports it everywhere while cloud cover
  /// is an area fraction rather than a presence. Below the floor it counts for nothing; at the
  /// ceiling it counts for everything. Shaped after the icing products' own ramp, which rises
  /// slowly to a tenth at 60% and quickly to full interest by 95%.
  private static let icingHumidityFloor = 0.60,
    icingHumidityCeiling = 0.95,
    icingHumidityFloorInterest = 0.1

  /// How much interest a level needs before it is drawn at all.
  ///
  /// A floor rather than a fade to nothing: the faintest interest covers half the sky on a damp
  /// day, and shading it would say more than a two-field model can support.
  private static let minimumIcingInterest = 0.25

  /// How much of the sky this level's cloud covers, in the categories an aviation report uses.
  var skyCover: SkyCover? { cloudCover.flatMap(SkyCover.init(fraction:)) }

  /// How strongly this level suggests structural icing, from zero to one.
  ///
  /// Graded rather than tested, after the FAA/NCAR icing products: each field becomes an interest
  /// from zero to one, and the interests combine. Those products weigh vertical velocity,
  /// supercooled liquid water, and cloud top temperature as well — none of which a pressure-level
  /// forecast publishes, so temperature and humidity carry this alone.
  ///
  /// This is a hint drawn from a forecast model, not an icing forecast product. It cannot tell
  /// humid air from cloud, and says nothing about severity or supercooled large drops.
  var icingInterest: Double {
    guard let temperatureC = temperature?.converted(to: .celsius).value,
      let relativeHumidity
    else { return 0 }
    return Self.temperatureInterest(atC: temperatureC)
      * Self.humidityInterest(relativeHumidity)
  }

  /// Whether this level is worth drawing as icing at all.
  var isIcing: Bool { icingInterest >= Self.minimumIcingInterest }

  /// How far above the drawing threshold this level stands, from zero to one.
  ///
  /// What the shading is graded by, so the drawn band runs from just-worth-mentioning to the
  /// middle of the icing band rather than from nothing to everything.
  var icingStrength: Double {
    let span = 1 - Self.minimumIcingInterest
    guard span > 0 else { return 1 }
    return max(0, min(1, (icingInterest - Self.minimumIcingInterest) / span))
  }

  /// Interest in the temperature alone: none at freezing, full across the supercooled band, and
  /// tapering to none where cloud has frozen out.
  private static func temperatureInterest(atC temperatureC: Double) -> Double {
    guard temperatureC < icingWarmLimitC, temperatureC > icingColdLimitC else { return 0 }
    if temperatureC >= icingPeakWarmC {
      return (icingWarmLimitC - temperatureC) / (icingWarmLimitC - icingPeakWarmC)
    }
    if temperatureC >= icingPeakColdC { return 1 }
    return (temperatureC - icingColdLimitC) / (icingPeakColdC - icingColdLimitC)
  }

  /// Interest in the humidity alone, ramping from the floor to the ceiling.
  private static func humidityInterest(_ relativeHumidity: Double) -> Double {
    guard relativeHumidity > icingHumidityFloor else { return 0 }
    guard relativeHumidity < icingHumidityCeiling else { return 1 }

    let fraction =
      (relativeHumidity - icingHumidityFloor) / (icingHumidityCeiling - icingHumidityFloor)
    return icingHumidityFloorInterest + fraction * (1 - icingHumidityFloorInterest)
  }
}

/// How much of the sky a cloud layer covers, in the categories an aviation report uses.
enum SkyCover: CaseIterable {
  case few, scattered, broken, overcast

  var label: String {
    switch self {
      case .few: String(localized: "Few")
      case .scattered: String(localized: "Scattered")
      case .broken: String(localized: "Broken")
      case .overcast: String(localized: "Overcast")
    }
  }

  /// How solidly the layer is drawn: continuous for an overcast, opening up as coverage thins.
  ///
  /// A dash pattern rather than a fading opacity, so the layers stay legible against terrain and
  /// read as coverage rather than as altitude uncertainty. Each pattern's mark covers roughly the
  /// share of the sky its category reports, so a deck's gaps say how much sky is open.
  var dash: [CGFloat] {
    switch self {
      case .few: [3, 15]
      case .scattered: [7, 9]
      case .broken: [14, 4]
      case .overcast: []
    }
  }

  /// The category a coverage fraction falls in, or `nil` for a sky clear enough to report nothing.
  ///
  /// - Parameter fraction: The sky covered, from zero to one.
  init?(fraction: Double) {
    switch fraction {
      case ..<0.125: return nil
      case ..<0.375: self = .few
      case ..<0.5625: self = .scattered
      case ..<0.875: self = .broken
      default: self = .overcast
    }
  }
}
