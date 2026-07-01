import CoreLocation
import Foundation
@preconcurrency import WeatherKit

// MARK: - Public Types

extension WeatherLoader {
  /// Errors that can occur during weather loading.
  public enum Errors: Swift.Error {
    /// HTTP response was not successful.
    case badResponse(_ response: HTTPURLResponse)

    /// Failed to decompress GZIP data.
    case gzipDecompressionFailed(
      url: URL,
      dataSize: Int,
      dataPrefix: String,
      underlyingError: any Swift.Error
    )

    /// Failed to decode data as UTF-8 text.
    case invalidTextEncoding(url: URL)
  }

  /// Key identifying a weather data request by airport and time.
  public struct Key: Hashable, Sendable {
    /// Weather station identifier (typically ICAO code).
    let id: String

    /// Winds aloft station identifier (FAA location ID).
    let windsAloftID: String

    /// Geographic location for WeatherKit requests.
    let location: CLLocation

    /// Time for which conditions are requested.
    let time: Date

    /// Weather station identifier (typically the ICAO code) for this request.
    public var stationID: String { id }

    /// Creates a key for the specified airport and time.
    /// - Parameters:
    ///   - airport: The airport to fetch weather for.
    ///   - time: The time for which conditions are needed.
    public init(airport: Airport, time: Date) {
      id = airport.weatherID
      windsAloftID = airport.locationID
      location = airport.location
      self.time = time
    }

    public func hash(into hasher: inout Hasher) {
      hasher.combine(id)
      hasher.combine(time)
    }
  }
}

// MARK: - Internal Types

extension WeatherLoader {
  struct Observation {
    let conditions: Conditions
    let raw: String
  }

  struct Forecast {
    let conditions: [Conditions]
    let raw: String
  }
}

// MARK: - Fileprivate Extensions

extension Airport {
  var weatherID: String {
    if let ICAO_ID { return ICAO_ID }
    if locationID.count == 3 { return "K\(locationID)" }
    return locationID
  }
}

extension HourWeather {
  var dateRange: DateInterval {
    .init(start: date, duration: 3600)
  }
}

extension Forecast<HourWeather> {
  func `for`(date: Date) -> HourWeather? {
    first(where: { $0.dateRange.contains(date) })
  }
}
