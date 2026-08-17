import Foundation
import SF50_Shared

/// Atmosphere loader that answers from a fixture instead of the network.
///
/// Used during UI testing so switching weather layers exercises the chart rather than a forecast
/// service. The mode is selected by a launch argument:
/// - `WEATHER-ISA` / `WEATHER-NWS` / `GENERATE-SCREENSHOTS`: a sample atmosphere
/// - `WEATHER-ERROR`: refuses as though there were no connection, which is how a go-around profile
///   planned in the air behaves
actor UITestingPathAtmosphereLoader: PathAtmosphereLoading {

  private let isOffline: Bool,
    isGeneratingScreenshots: Bool

  init() {
    isOffline = ProcessInfo.processInfo.arguments.contains("WEATHER-ERROR")
    isGeneratingScreenshots = UITestingHelper.isGeneratingScreenshots
  }

  func atmosphere(
    along points: [PathAtmosphereLoader.PathPoint],
    at _: Date
  ) throws -> PathAtmosphere {
    if isOffline { throw PathAtmosphereLoader.Failure.offline }
    // The screenshots are shot at a mountain airport, where the sample column below reads as an
    // arctic day by the time it reaches the field.
    if isGeneratingScreenshots { return .previewMountain }
    guard let last = points.last, last.distanceNM > PathAtmosphereLoader.columnRadiusNM else {
      return .preview
    }
    return .previewMultiColumn
  }
}
