import Foundation
@preconcurrency import WeatherKit

extension WeatherLoader {
  /// How much of the hourly forecast one lookup asks for.
  ///
  /// Two hours, though the answer only ever comes from the first: the query's end date is exclusive,
  /// so a window closing on the boundary of the very hour being asked about can come back empty. The
  /// trailing hour costs nothing to fetch and leaves the hour covering the requested time first.
  private static let hourlyQuerySpan: TimeInterval = 2 * 3600

  /// The conditions at an airport for a time, drawn from every service that has them.
  ///
  /// The aviation report is authoritative and taken first, but reports only what its station
  /// measures: a TAF carries no temperature at all, and a METAR may omit an altimeter setting.
  /// Whatever it leaves out is filled in from Open-Meteo, and from Apple WeatherKit after that.
  /// Each supplement is skipped once nothing is left to fill, so WeatherKit is reached only where
  /// Open-Meteo couldn't answer.
  ///
  /// - Parameter key: Identifies the airport and time.
  /// - Returns: The conditions, or ISA where no service had any.
  func conditions(for key: Key) async -> Loadable<Conditions> {
    let reported = aviationConditions(for: key)
    guard case .value(let reported) = reported else { return reported.map { _ in .init() } }
    return .value(await supplementing(reported, for: key))
  }

  /// The METAR or TAF conditions published for a key, or `nil` if none covers it.
  ///
  /// An observation stands for the hour it was taken in; past that, the forecast period covering
  /// the requested time is used instead.
  private func aviationConditions(for key: Key) -> Loadable<Conditions?> {
    guard key.isCurrent else {
      return forecasts.map { forecasts in
        forecasts[key.id]?.conditions.first { $0.validTime.contains(key.time) }
      }
    }
    return observations.map { $0[key.id]?.conditions }
  }

  /// Fills the values an aviation report leaves unreported from the forecast models.
  private func supplementing(_ reported: Conditions?, for key: Key) async -> Conditions {
    var conditions = reported

    if conditions?.isComplete != true, let openMeteo = await openMeteoConditions(for: key) {
      conditions = conditions?.filling(from: openMeteo) ?? openMeteo
    }
    if conditions?.isComplete != true, let weatherKit = await weatherKitConditions(for: key) {
      conditions = conditions?.filling(from: weatherKit) ?? weatherKit
    }

    return conditions ?? .init()
  }

  /// Open-Meteo's conditions for a key, or `nil` if it has none or couldn't be reached.
  ///
  /// A supplement that fails leaves the aviation report as it stands rather than failing the whole
  /// lookup, so the failure is recorded and swallowed.
  private func openMeteoConditions(for key: Key) async -> Conditions? {
    do {
      return try await OpenMeteoService.shared.conditions(for: key)
    } catch {
      Self.recordLoadFailure(error, dataType: "openMeteo", airport: key.id)
      return nil
    }
  }

  /// WeatherKit's conditions for a key, or `nil` if it has none or couldn't be reached.
  ///
  /// Only the one dataset the key calls for is requested. Asking for the whole `Weather` bundle
  /// would fetch the minute, daily, alert, and availability sets alongside it — for every airport,
  /// on every load, over whatever connectivity an FBO or a cockpit has — and discard all of them.
  private func weatherKitConditions(for key: Key) async -> Conditions? {
    do {
      guard key.isCurrent else { return try await forecastConditions(for: key) }
      return try await currentConditions(for: key)
    } catch {
      Self.recordLoadFailure(error, dataType: "weatherKit", airport: key.id)
      return nil
    }
  }

  /// WeatherKit's reading of the conditions at a key's location as they stand.
  private func currentConditions(for key: Key) async throws -> Conditions {
    let current = try await Self.weatherService.weather(for: key.location, including: .current)
    return .init(weather: current)
  }

  /// WeatherKit's forecast for the hour a key's time falls in, or `nil` if it doesn't reach that far
  /// ahead.
  private func forecastConditions(for key: Key) async throws -> Conditions? {
    let hour = key.time.startOfHour
    let forecast = try await Self.weatherService.weather(
      for: key.location,
      including: .hourly(startDate: hour, endDate: hour + Self.hourlyQuerySpan)
    )
    return forecast.first.map { .init(weather: $0) }
  }
}

extension WeatherLoader.Key {
  /// Whether the requested time is near enough to now to be served by a current observation.
  fileprivate var isCurrent: Bool { time.timeIntervalSinceNow < 3600 }
}
