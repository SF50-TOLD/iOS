import Foundation

func ftNMToRatio(_ value: Double) -> Double {
  Measurement(value: value, unit: UnitLength.feet)
    / Measurement(value: 1, unit: UnitLength.nauticalMiles)
}

func ratioToFtNM(_ value: Double) -> Double {
  Measurement(value: value, unit: UnitLength.nauticalMiles)
    / Measurement(value: 1, unit: UnitLength.feet)
}
