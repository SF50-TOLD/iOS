public import Foundation

/// The services a set of weather values was drawn from.
///
/// Downloaded weather is assembled from whichever services answered: an aviation report supplies
/// what it reports and the rest is filled in from a forecast model. Recording which of them
/// contributed is what lets the app credit them — Open-Meteo publishes under CC-BY 4.0 and Apple
/// requires the Apple Weather trademark wherever WeatherKit data is shown.
public struct WeatherProviders: OptionSet, Sendable, Hashable {

  /// The National Weather Service, via Aviation Weather's METAR, TAF, and winds aloft products.
  public static let NWS = Self(rawValue: 1 << 0)

  /// [Open-Meteo](https://open-meteo.com), a forecast model API.
  public static let openMeteo = Self(rawValue: 1 << 1)

  /// Apple WeatherKit.
  public static let weatherKit = Self(rawValue: 1 << 2)

  /// Where Open-Meteo's CC-BY 4.0 licence requires its credit to point.
  public static let openMeteoURL = URL(string: "https://open-meteo.com")!

  private static let openMeteoName = String(localized: "Open-Meteo")

  /// Open-Meteo's name, linked to its site — the credit its CC-BY 4.0 licence asks for.
  public static let openMeteoCredit: AttributedString = {
    var credit = AttributedString(openMeteoName)
    credit.link = openMeteoURL
    return credit
  }()

  private static let namesInPrecedenceOrder: [(provider: Self, name: String)] = [
    (.NWS, String(localized: "NWS")),
    (.openMeteo, openMeteoName),
    (.weatherKit, String(localized: "Apple Weather"))
  ]

  public let rawValue: Int

  /// The names of the contributing services, most authoritative first.
  public var localizedNames: [String] {
    Self.namesInPrecedenceOrder.filter { contains($0.provider) }.map(\.name)
  }

  /// The contributing services as a phrase, e.g. “NWS and Open-Meteo”.
  public var localizedDescription: String {
    localizedNames.formatted(.list(type: .and))
  }

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }
}
