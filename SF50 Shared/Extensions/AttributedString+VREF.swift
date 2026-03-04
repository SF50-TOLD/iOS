import SwiftUI

extension AttributedString {
  public static var VREF: AttributedString {
    let v = AttributedString("V")
    var ref = AttributedString("REF")
    ref.font = .system(size: 10.0)
    ref.baselineOffset = -3.0
    return v + ref
  }
}
