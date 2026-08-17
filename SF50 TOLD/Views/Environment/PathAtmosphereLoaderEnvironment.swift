import SF50_Shared
import SwiftUI

private struct PathAtmosphereLoaderKey: EnvironmentKey {
  static let defaultValue: any PathAtmosphereLoading = PathAtmosphereLoader.shared
}

extension EnvironmentValues {
  /// Where the weather layers of a terrain profile fetch their atmosphere from.
  ///
  /// Injected so a UI test can stand in for the network: a test that switches weather layers
  /// should exercise the chart, not a forecast service.
  var pathAtmosphereLoader: any PathAtmosphereLoading {
    get { self[PathAtmosphereLoaderKey.self] }
    set { self[PathAtmosphereLoaderKey.self] = newValue }
  }
}
