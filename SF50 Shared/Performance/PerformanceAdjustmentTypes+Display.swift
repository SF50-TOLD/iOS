public import Foundation
import MeasurementKit
import SwiftUI

extension AdjustmentKind {
  /// Localized attributed description with subscripted VREF where applicable.
  public var localizedAttributedDescription: AttributedString {
    switch self {
      case .VREFAdditive(let speed):
        .VREF
          + AttributedString(
            localized: " — \(speed.asSpeed, format: .speed(plusSign: true))",
            bundle: .sharedFramework
          )
      default:
        AttributedString(localizedDescription(units: .preferred))
    }
  }
}

extension PerformanceNote {
  /// Localized description in the pilot's preferred units.
  public var preferredDescription: String { localizedDescription(units: .preferred) }
}
