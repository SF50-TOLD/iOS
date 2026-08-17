import Foundation
import SF50_Shared

/// Weather loader that returns pre-determined conditions based on launch arguments.
///
/// Used during UI testing to eliminate network weather requests and race conditions.
/// The mode is selected by a launch argument:
/// - `WEATHER-ISA` (default): ISA standard conditions
/// - `WEATHER-NWS`: Fake NWS-sourced conditions (wind 350@15, temp 21°C, altimeter 30.05)
/// - `WEATHER-ERROR`: Simulates a weather download failure
/// - `GENERATE-SCREENSHOTS`: Believable per-airport NWS conditions and raw METAR/TAF, so
///   App Store screenshots showcase headwind/crosswind and observation text instead of the
///   bare “No weather — using ISA” fallback.
actor UITestingWeatherLoader: WeatherLoaderProtocol {

  private static let fakeMETAR = "KOAK 010000Z 35015KT 10SM FEW200 21/10 A3005"
  private static let fakeTAF =
    "TAF KOAK 010000Z 0100/0124 35015KT P6SM FEW200"
  private static let screenshotWeatherByStation: [String: FakeWeather] = [
    // Aspen-Pitkin County (7,838 ft): a warm afternoon up-valley wind that yields a healthy
    // headwind on Rwy 33 and a tailwind on the reciprocal Rwy 15, plus a high density
    // altitude — exactly the conditions the app is built to evaluate.
    "KASE": .init(
      conditions: .fakeNWS(
        windDirection: .init(value: 290, unit: .degrees),
        windSpeed: .init(value: 12, unit: .knots),
        temperature: .init(value: 18, unit: .celsius),
        seaLevelPressure: .init(value: 30.12, unit: .inchesOfMercury)
      ),
      metar: "KASE 121553Z 29012KT 10SM FEW120 SCT220 18/04 A3012 RMK AO2 SLP146 T01780039",
      taf:
        "KASE 121130Z 1212/1312 29010KT P6SM FEW120 SCT200 "
        + "FM121800 30013G20KT P6SM SCT150 BKN220"
    )
  ]

  private let mode: Mode

  init() {
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains(Mode.screenshots.rawValue) {
      mode = .screenshots
    } else if arguments.contains(Mode.NWS.rawValue) {
      mode = .NWS
    } else if arguments.contains(Mode.error.rawValue) {
      mode = .error
    } else {
      mode = .ISA
    }
  }

  /// Believable conditions and observation text for the given weather station, used to populate
  /// App Store screenshots. Falls back to a generic but realistic report for unlisted airports.
  private static func screenshotWeather(for id: String) -> FakeWeather {
    screenshotWeatherByStation[id] ?? .generic(station: id)
  }

  func load(force _: Bool) {}

  func cancelLoading() {}

  func streamConditions(for key: WeatherLoader.Key) -> AsyncStream<Loadable<Conditions>> {
    let mode = self.mode
    let id = key.stationID
    return AsyncStream { continuation in
      switch mode {
        case .ISA:
          continuation.yield(.value(.init()))
        case .NWS:
          continuation.yield(.value(.fakeNWS()))
        case .screenshots:
          continuation.yield(.value(Self.screenshotWeather(for: id).conditions))
        case .error:
          continuation.yield(.error(UITestingWeatherError()))
      }
    }
  }

  func streamMETAR(for key: WeatherLoader.Key) -> AsyncStream<Loadable<String?>> {
    let mode = self.mode
    let id = key.stationID
    return AsyncStream { continuation in
      switch mode {
        case .NWS:
          continuation.yield(.value(Self.fakeMETAR))
        case .screenshots:
          continuation.yield(.value(Self.screenshotWeather(for: id).metar))
        default:
          continuation.yield(.notLoaded)
      }
    }
  }

  func streamTAF(for key: WeatherLoader.Key) -> AsyncStream<Loadable<String?>> {
    let mode = self.mode
    let id = key.stationID
    return AsyncStream { continuation in
      switch mode {
        case .NWS:
          continuation.yield(.value(Self.fakeTAF))
        case .screenshots:
          continuation.yield(.value(Self.screenshotWeather(for: id).taf))
        default:
          continuation.yield(.notLoaded)
      }
    }
  }

  /// Winds aloft for the modes that report weather at all.
  ///
  /// ISA mode stays unreported: it stands for having no downloaded weather, and a climb profile
  /// built on it should show the calm column and the "no winds aloft forecast" note. The reporting
  /// modes serve a bulletin-shaped forecast whose lowest level is 3,000 ft, so the profile's wind
  /// layer exercises carrying that level down to the field.
  func streamWindsAloft(for _: WeatherLoader.Key) -> AsyncStream<Loadable<WindsAloftForecast?>> {
    AsyncStream { continuation in
      switch mode {
        case .NWS, .screenshots:
          continuation.yield(.value(.preview))
        default:
          continuation.yield(.notLoaded)
      }
    }
  }

  enum Mode: String {
    case ISA = "WEATHER-ISA"
    case NWS = "WEATHER-NWS"
    case error = "WEATHER-ERROR"
    case screenshots = "GENERATE-SCREENSHOTS"
  }

  /// A self-consistent fake observation: parsed ``Conditions`` paired with matching raw
  /// METAR and TAF text for display.
  private struct FakeWeather {
    let conditions: Conditions
    let metar: String
    let taf: String

    /// A realistic default report for airports without a hand-tuned entry, keyed off the
    /// station identifier so the displayed text always matches the requested field.
    static func generic(station: String) -> Self {
      .init(
        conditions: .fakeNWS(
          windDirection: .init(value: 280, unit: .degrees),
          windSpeed: .init(value: 9, unit: .knots),
          temperature: .init(value: 20, unit: .celsius),
          seaLevelPressure: .init(value: 30.08, unit: .inchesOfMercury)
        ),
        metar: "\(station) 121553Z 28009KT 10SM FEW090 SCT200 20/08 A3008 RMK AO2",
        taf:
          "\(station) 121130Z 1212/1312 28008KT P6SM FEW090 SCT200 "
          + "FM121800 29011KT P6SM SCT150 BKN220"
      )
    }
  }
}

private struct UITestingWeatherError: LocalizedError {
  var errorDescription: String? { "Couldn\u{2019}t load weather." }
  var failureReason: String? { "Weather loading is disabled during UI testing." }
}
