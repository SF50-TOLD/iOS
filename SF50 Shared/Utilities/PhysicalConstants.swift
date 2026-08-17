import Foundation

// MARK: - Earth

/// Mean radius of the Earth in meters.
public let earthRadiusM: Double = 6_371_000

/// Meters per nautical mile (exact by definition).
private let metersPerNauticalMile: Double = 1852

// MARK: - Standard Atmosphere (ISA)

/// ISA sea-level temperature in Kelvin.
private let seaLevelStandardTempK: Double = 288.15

/// ISA sea-level temperature in °C.
public let seaLevelStandardTempC: Double = seaLevelStandardTempK - celsiusToKelvinOffset

/// ISA temperature lapse rate in K/m (troposphere).
private let tempLapseRateKPerM: Double = 0.0065

/// ISA temperature lapse rate in °C/ft (troposphere).
private let tempLapseRateCPerFt: Double = tempLapseRateKPerM * feetToMeters

/// ISA sea-level air density in kg/m³.
private let seaLevelStandardDensityKgM3: Double = 1.225

/// Standard sea level pressure in hectopascals (ISA standard: 1013.25 hPa).
public let standardSeaLevelPressureHPa: Double = 1013.25

/// Standard temperature at sea level (ISA standard: 15°C).
public let standardTemperature = Measurement(
  value: seaLevelStandardTempC,
  unit: UnitTemperature.celsius
)

/// Standard sea level pressure (ISA standard: 1013.25 hPa / 29.92 inHg).
public let standardSeaLevelPressure = Measurement(
  value: standardSeaLevelPressureHPa,
  unit: UnitPressure.hectopascals
)

// MARK: - Thermodynamics

/// Standard gravity in m/s².
private let standardGravity: Double = 9.80665

/// Molar mass of dry air in kg/mol.
private let molarMassAir: Double = 0.0289644

/// Universal gas constant in J/(mol·K).
private let universalGasConstant: Double = 8.31447

/// Specific gas constant for dry air in J/(kg·K).
private let specificGasConstantDryAir: Double = 287.058

/// Barometric formula exponent: gM/(RL).
private let barometricExponent: Double =
  (standardGravity * molarMassAir) / (universalGasConstant * tempLapseRateKPerM)

/// Speed of sound coefficient for knots: a = coefficient × √(T_K).
private let speedOfSoundCoefficientKts: Double = 38.967854

// MARK: - Unit Conversions

/// Feet to meters conversion factor.
public let feetToMeters: Double = 0.3048

/// Feet per nautical mile.
public let feetPerNauticalMile: Double = metersPerNauticalMile / feetToMeters

/// Offset to convert Celsius to Kelvin.
private let celsiusToKelvinOffset: Double = 273.15

/// Inches of mercury to Pascals conversion factor.
public let inHgToPa: Double = 3386.39

// MARK: - Atmospheric Functions

/// ISA temperature at altitude in °C.
public func isaTemperature(altitudeFt: Double) -> Double {
  seaLevelStandardTempC - tempLapseRateCPerFt * altitudeFt
}

/// The standard-atmosphere temperature at an altitude.
///
/// - Parameter altitude: The altitude to read.
/// - Returns: The ISA temperature there.
public func ISATemperature(at altitude: Measurement<UnitLength>) -> Measurement<UnitTemperature> {
  .init(value: isaTemperature(altitudeFt: altitude.converted(to: .feet).value), unit: .celsius)
}

/// Pressure at altitude using the barometric formula (troposphere).
///
/// - Parameters:
///   - seaLevelPressurePa: Sea-level pressure in Pascals.
///   - altitudeM: Altitude in meters.
/// - Returns: Pressure at altitude in Pascals.
public func pressureAtAltitude(seaLevelPressurePa: Double, altitudeM: Double) -> Double {
  seaLevelPressurePa
    * pow(
      1.0 - (tempLapseRateKPerM * altitudeM / seaLevelStandardTempK),
      barometricExponent
    )
}

/// Air density from pressure and temperature.
///
/// - Parameters:
///   - pressurePa: Pressure in Pascals.
///   - temperatureC: Temperature in °C.
/// - Returns: Air density in kg/m³.
public func airDensity(pressurePa: Double, temperatureC: Double) -> Double {
  let T = temperatureC + celsiusToKelvinOffset
  return pressurePa / (specificGasConstantDryAir * T)
}

/// True airspeed from indicated airspeed given pressure and temperature.
///
/// TAS = IAS × √(ρ₀/ρ)
///
/// - Parameters:
///   - indicatedAirspeedKts: Indicated airspeed in knots.
///   - pressurePa: Pressure at altitude in Pascals.
///   - temperatureC: Outside air temperature in °C.
/// - Returns: True airspeed in knots.
public func trueAirspeed(indicatedAirspeedKts: Double, pressurePa: Double, temperatureC: Double)
  -> Double
{
  let ρ = airDensity(pressurePa: pressurePa, temperatureC: temperatureC)
  return indicatedAirspeedKts * (seaLevelStandardDensityKgM3 / ρ).squareRoot()
}

/// Speed of sound in knots from outside air temperature.
///
/// - Parameter OATC: Outside air temperature in °C.
/// - Returns: Speed of sound in knots.
public func speedOfSound(OATC: Double) -> Double {
  speedOfSoundCoefficientKts * (OATC + celsiusToKelvinOffset).squareRoot()
}

/// NWS dry-air density altitude approximation.
///
/// - Parameters:
///   - stationPressureInHg: Station pressure in inches of mercury.
///   - temperatureF: Temperature in °F.
/// - Returns: Density altitude in feet.
public func densityAltitude(stationPressureInHg: Double, temperatureF: Double) -> Double {
  145442.16 * (1.0 - pow((17.326 * stationPressureInHg) / (459.67 + temperatureF), 0.235))
}
