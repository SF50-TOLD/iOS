import Foundation

/// The units a terrain profile is plotted in, and the conversions onto and off its axes.
///
/// The path carries feet and nautical miles; the chart's scales carry whatever the pilot asked to
/// see. Both axes are converted rather than only their tick labels, so `AxisMarks` still picks round
/// numbers in the unit actually shown.
///
/// Everything the chart reasons about — clearances, restriction violations, terrain impacts — stays
/// in the path's own feet and nautical miles. Only the values handed to a mark, and the values read
/// back out of a `ChartProxy`, pass through here.
struct TerrainProfileScale: Equatable {

  /// The unit altitudes are plotted in.
  let heightUnit: UnitLength

  /// The unit along-path distances are plotted in.
  let distanceUnit: UnitLength

  /// Where an altitude in feet MSL falls on the altitude axis.
  func axisAltitude(ft altitudeFt: Double) -> Double {
    axisAltitude(.init(value: altitudeFt, unit: .feet))
  }

  /// Where an altitude falls on the altitude axis.
  func axisAltitude(_ altitude: Measurement<UnitLength>) -> Double {
    altitude.converted(to: heightUnit).value
  }

  /// Where a distance in nautical miles from the path origin falls on the distance axis.
  func axisDistance(nm distanceNM: Double) -> Double {
    Measurement(value: distanceNM, unit: UnitLength.nauticalMiles).converted(to: distanceUnit).value
  }

  /// The altitude a value on the altitude axis stands for.
  func altitude(atAxisValue value: Double) -> Measurement<UnitLength> {
    .init(value: value, unit: heightUnit)
  }

  /// The distance in nautical miles a value on the distance axis stands for.
  func distanceNM(atAxisValue value: Double) -> Double {
    Measurement(value: value, unit: distanceUnit).converted(to: .nauticalMiles).value
  }
}
