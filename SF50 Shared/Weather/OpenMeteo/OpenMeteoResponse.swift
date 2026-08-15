import Foundation

/// An hourly forecast for one location, as Open-Meteo returns it.
///
/// The response is column-oriented: `hourly` holds one array per requested variable, all the same
/// length and aligned to a shared array of timestamps. Variable names carry the pressure level they
/// were requested at — `temperature_850hPa` — so the columns can't be spelled as coding keys and
/// are read by name instead. See ``OpenMeteoVariable``.
struct OpenMeteoResponse: Decodable, Sendable {

  private static let hourDuration: TimeInterval = 3600

  /// The elevation of the model's terrain at this location.
  ///
  /// The model reports pressure levels that stand below its own ground, extrapolated rather than
  /// forecast, so this is what tells a usable level from one that isn't.
  let elevation: Measurement<UnitLength>

  /// The hourly forecast columns.
  let hourly: Hourly

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    elevation = .init(value: try container.decode(Double.self, forKey: .elevation), unit: .meters)
    hourly = try container.decode(Hourly.self, forKey: .hourly)
  }

  /// The forecast hour covering a time, or `nil` if the response doesn't reach it.
  ///
  /// The hours are half-open: a time falling exactly on the hour belongs to the hour it begins,
  /// not to the one it ends.
  ///
  /// - Parameter time: The time weather is needed for.
  /// - Returns: The hour containing `time`.
  func hour(covering time: Date) -> Hour? {
    guard let index = hourly.times.lastIndex(where: { $0 <= time }),
      time.timeIntervalSince(hourly.times[index]) < Self.hourDuration
    else { return nil }
    return .init(hourly: hourly, index: index)
  }

  private enum CodingKeys: String, CodingKey {
    case elevation, hourly
  }

  /// The hourly forecast columns: a timestamp array and one value array per variable.
  struct Hourly: Decodable, Sendable {

    /// The time each column entry applies to.
    let times: [Date]

    private let columns: [String: [Double?]]

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: VariableKey.self)
      times = try container.decode([Date].self, forKey: .init(OpenMeteoVariable.time))

      // A variable the model doesn't publish is omitted rather than sent as a column of nulls, so
      // the requested names are not necessarily the ones that came back.
      columns = try container.allKeys
        .filter { $0.stringValue != OpenMeteoVariable.time }
        .reduce(into: [:]) { columns, key in
          columns[key.stringValue] = try container.decode([Double?].self, forKey: key)
        }
    }

    /// A variable's value at an hour, or `nil` where the model doesn't report it.
    ///
    /// - Parameters:
    ///   - variable: The variable name; see ``OpenMeteoVariable``.
    ///   - index: The hour to read, as an index into ``times``.
    /// - Returns: The reported value.
    func value(of variable: String, at index: Int) -> Double? {
      guard let column = columns[variable], column.indices.contains(index) else { return nil }
      return column[index]
    }

    /// A coding key for a column named at runtime.
    private struct VariableKey: CodingKey {
      let stringValue: String
      var intValue: Int? { nil }

      init(_ stringValue: String) { self.stringValue = stringValue }
      init?(stringValue: String) { self.init(stringValue) }
      init?(intValue _: Int) { nil }
    }
  }

  /// One hour of the forecast.
  struct Hour: Sendable {
    let hourly: Hourly
    let index: Int

    /// The period this hour covers.
    var interval: DateInterval { hourly.times[index].hourInterval }

    /// A variable's value this hour, or `nil` where the model doesn't report it.
    /// - Parameter variable: The variable name; see ``OpenMeteoVariable``.
    /// - Returns: The reported value.
    func value(of variable: String) -> Double? { hourly.value(of: variable, at: index) }
  }
}

extension Date {
  /// The hour beginning at this time.
  ///
  /// Open-Meteo timestamps an hourly value at the start of the hour it applies to.
  fileprivate var hourInterval: DateInterval { .init(start: self, duration: 3600) }
}

/// The body Open-Meteo returns in place of a forecast when it rejects a request.
struct OpenMeteoErrorResponse: Decodable, Sendable {
  let error: Bool
  let reason: String
}
