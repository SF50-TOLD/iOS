public import Foundation

extension WeatherProviders {
  /// Open-Meteo's name, linked to its site — the credit its CC-BY 4.0 licence asks for.
  public static let openMeteoCredit: AttributedString = {
    var credit = AttributedString(openMeteoName)
    credit.link = openMeteoURL
    return credit
  }()
}
