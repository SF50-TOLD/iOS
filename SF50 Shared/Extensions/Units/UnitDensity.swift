import Foundation

/// A unit of density (mass per unit volume).
///
/// ``UnitDensity`` provides units for measuring density, which is a substance's
/// mass per unit of volume (ρ = m/V). This is used in SF50 TOLD for fuel density
/// calculations when converting between fuel volume and weight.
///
/// ## Common Units
///
/// - ``kilogramsPerLiter`` (base unit)
/// - ``poundsPerGallon`` (aviation standard for fuel)
///
/// ## Usage
///
/// ```swift
/// let fuelDensity = Measurement(value: 6.0, unit: UnitDensity.poundsPerGallon)
/// let metricDensity = fuelDensity.converted(to: .kilogramsPerLiter)
/// ```
@preconcurrency
public class UnitDensity: Dimension, @unchecked Sendable {

  /// Kilograms per liter (kg/L)
  public static let kilogramsPerLiter: UnitDensity = unit(
    UnitMass.kilograms,
    per: UnitVolume.liters
  )

  /// Pounds per gallon (lb/gal)
  public static let poundsPerGallon: UnitDensity = unit(UnitMass.pounds, per: UnitVolume.gallons)

  override public class func baseUnit() -> Self { kilogramsPerLiter as! Self }
}
