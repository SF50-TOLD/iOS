import SwiftUI

#if canImport(UIKit)
  import UIKit

  extension View {
    func localizedModel() -> String {
      UIDevice.current.localizedModel
    }
  }
#else
  extension View {
    func localizedModel() -> String {
      "device"
    }
  }
#endif
