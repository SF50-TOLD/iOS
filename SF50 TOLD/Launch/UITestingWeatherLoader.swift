import CoreLocation
import Foundation
import SF50_Shared

/// Weather loader that returns pre-determined conditions based on launch arguments.
///
/// Used during UI testing to eliminate network weather requests and race conditions.
/// The mode is selected by a launch argument:
/// - `WEATHER-ISA` (default): ISA standard conditions
/// - `WEATHER-NWS`: Fake NWS-sourced conditions (wind 350@15, temp 21°C, altimeter 30.05)
/// - `WEATHER-ERROR`: Simulates a weather download failure
actor UITestingWeatherLoader: WeatherLoaderProtocol {

  private static let fakeMETAR = "KOAK 010000Z 35015KT 10SM FEW200 21/10 A3005"
  private static let fakeTAF =
    "TAF KOAK 010000Z 0100/0124 35015KT P6SM FEW200"

  private let mode: Mode

  init() {
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains(Mode.NWS.rawValue) {
      mode = .NWS
    } else if arguments.contains(Mode.error.rawValue) {
      mode = .error
    } else {
      mode = .ISA
    }
  }

  func load(force _: Bool) {}

  func cancelLoading() {}

  func streamConditions(for _: WeatherLoader.Key) -> AsyncStream<Loadable<Conditions>> {
    let mode = self.mode
    return AsyncStream { continuation in
      switch mode {
        case .ISA:
          continuation.yield(.value(.init()))
        case .NWS:
          continuation.yield(.value(.fakeNWS()))
        case .error:
          continuation.yield(.error(UITestingWeatherError()))
      }
    }
  }

  func streamMETAR(for _: WeatherLoader.Key) -> AsyncStream<Loadable<String?>> {
    let mode = self.mode
    return AsyncStream { continuation in
      switch mode {
        case .NWS:
          continuation.yield(.value(Self.fakeMETAR))
        default:
          continuation.yield(.notLoaded)
      }
    }
  }

  func streamTAF(for _: WeatherLoader.Key) -> AsyncStream<Loadable<String?>> {
    let mode = self.mode
    return AsyncStream { continuation in
      switch mode {
        case .NWS:
          continuation.yield(.value(Self.fakeTAF))
        default:
          continuation.yield(.notLoaded)
      }
    }
  }

  func streamWindsAloft(for _: WeatherLoader.Key) -> AsyncStream<Loadable<WindsAloftData?>> {
    AsyncStream { continuation in
      continuation.yield(.notLoaded)
    }
  }

  func interpolatedWindsAloft(
    at _: CLLocationCoordinate2D,
    altitude _: Measurement<UnitLength>
  ) -> WindsAloftData.Entry? {
    nil
  }

  enum Mode: String {
    case ISA = "WEATHER-ISA"
    case NWS = "WEATHER-NWS"
    case error = "WEATHER-ERROR"
  }
}

private struct UITestingWeatherError: LocalizedError {
  var errorDescription: String? { "Couldn\u{2019}t load weather." }
  var failureReason: String? { "Weather loading is disabled during UI testing." }
}
