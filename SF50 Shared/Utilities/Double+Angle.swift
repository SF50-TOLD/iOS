import Foundation

extension Double {

  /// This value normalized to [0, 360), treating it as an angle in degrees.
  public var normalizedAngle: Double {
    let mod = truncatingRemainder(dividingBy: 360)
    return mod < 0 ? mod + 360 : mod
  }
}
