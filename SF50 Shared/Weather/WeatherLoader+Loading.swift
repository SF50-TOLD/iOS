import Foundation
import Gzip
import Logging
import Sentry
import SwiftMETAR

extension WeatherLoader {
  /// Whether `error` is Aviation Weather failing on its own end rather than a defect here.
  ///
  /// Its CDN intermittently answers `5xx`, and a cache file being regenerated is served
  /// as an empty body. A body that arrives corrupt is excluded: that is a real contract
  /// break worth knowing about.
  static func isUpstreamServerFailure(_ error: some Swift.Error) -> Bool {
    switch error as? Errors {
      case .badResponse(let response): (500..<600).contains(response.statusCode)
      case .emptyResponse: true
      default: false
    }
  }

  /// Whether `error` points at a defect in this app, and so belongs in Sentry.
  ///
  /// A cancelled load, a network the pilot has no coverage on, and Aviation Weather
  /// failing on its own end are all outside this app's control. Those are logged and
  /// surfaced to the pilot, who decides whether to retry.
  static func shouldReport(_ error: some Swift.Error) -> Bool {
    !error.isNetworkCancellation && !error.isTransientNetworkError
      && !isUpstreamServerFailure(error)
  }

  /// Logs a weather-load failure, reporting only genuine defects to Sentry.
  ///
  /// - Parameters:
  ///   - error: The failure.
  ///   - dataType: Which feed failed, which tags and fingerprints the report.
  ///   - airport: The airport being loaded, for feeds fetched per airport.
  static func recordLoadFailure(
    _ error: some Swift.Error,
    dataType: String,
    airport: String? = nil
  ) {
    // A load cancelled by moving on to another airport is routine and not worth a line.
    guard !error.isNetworkCancellation else { return }

    guard shouldReport(error) else {
      logger.info(
        "Not reporting weather load failure; cause is outside this app",
        metadata: ["error": "\(error)", "dataType": "\(dataType)"]
      )
      return
    }

    SentrySDK.capture(error: error) { scope in
      scope.setLevel(.warning)
      scope.setTag(value: dataType, key: "weather.dataType")
      if let airport { scope.setTag(value: airport, key: "airport") }
      scope.setFingerprint(["weather-loading", dataType])
    }
    logger.error(
      "Failed to load weather data",
      metadata: ["error": "\(error)", "dataType": "\(dataType)"]
    )
  }

  func loadMETARs() async {
    observations = .loading
    await notifySubscribers()

    do {
      try Task.checkCancellation()
      let data = try await load(url: Self.METARsURL)
      try Task.checkCancellation()

      let newMETARs = try await withThrowingTaskGroup(of: (String, Observation)?.self) { group in
        let xmlData: Data
        do {
          xmlData = try data.gunzipped()
        } catch {
          let prefix = data.prefix(20).map { unsafe String(format: "%02x", $0) }.joined(
            separator: " "
          )
          Self.logger.error(
            "Failed to decompress METAR data",
            metadata: [
              "error": "\(error)",
              "dataSize": "\(data.count)",
              "dataPrefix": "\(prefix)"
            ]
          )
          throw Errors.gzipDecompressionFailed(
            url: Self.METARsURL,
            dataSize: data.count,
            dataPrefix: prefix,
            underlyingError: error
          )
        }

        // Parse XML using SwiftMETAR
        for await result in SwiftMETAR.METAR.from(xml: xmlData) {
          try Task.checkCancellation()

          switch result {
            case .success(let metar):
              group.addTask {
                let conditions = Conditions(observation: metar)
                return (metar.stationID, .init(conditions: conditions, raw: metar.text ?? ""))
              }
            case .failure(let error, let rawText):
              if let rawText {
                do {
                  let metar = try await METAR.from(string: rawText)
                  group.addTask {
                    let conditions = Conditions(observation: metar)
                    return (metar.stationID, .init(conditions: conditions, raw: rawText))
                  }
                } catch {
                  Self.logger.warning(
                    "Failed to parse METAR from XML and text",
                    metadata: ["xmlError": "\(error)"]
                  )
                }
              } else {
                Self.logger.warning(
                  "Failed to parse METAR",
                  metadata: ["error": "\(error)"]
                )
              }
          }
        }

        return try await group.compactMap(\.self).reduce(into: [:]) { result, pair in
          result[pair.0] = pair.1
        }
      }

      observations = .value(newMETARs)
    } catch {
      // Don't update observations if cancelled
      guard !error.isNetworkCancellation else { return }
      Self.recordLoadFailure(error, dataType: "metar")
      observations = .error(error)
    }
  }

  func loadTAFs() async {
    forecasts = .loading
    await notifySubscribers()

    do {
      try Task.checkCancellation()
      let data = try await load(url: Self.TAFsURL)
      try Task.checkCancellation()

      let newTAFs = try await withThrowingTaskGroup(of: (String, Forecast)?.self) { group in
        let xmlData: Data
        do {
          xmlData = try data.gunzipped()
        } catch {
          let prefix = data.prefix(20).map { unsafe String(format: "%02x", $0) }.joined(
            separator: " "
          )
          Self.logger.error(
            "Failed to decompress TAF data",
            metadata: [
              "error": "\(error)",
              "dataSize": "\(data.count)",
              "dataPrefix": "\(prefix)"
            ]
          )
          throw Errors.gzipDecompressionFailed(
            url: Self.TAFsURL,
            dataSize: data.count,
            dataPrefix: prefix,
            underlyingError: error
          )
        }

        // Parse XML using SwiftMETAR
        for await result in SwiftMETAR.TAF.from(xml: xmlData) {
          try Task.checkCancellation()

          switch result {
            case .success(let taf):
              group.addTask {
                let conditions = taf.groups.compactMap { Conditions(forecast: $0) }
                return (taf.airportID, .init(conditions: conditions, raw: taf.text ?? ""))
              }
            case .failure(let error, let rawText):
              if let rawText {
                do {
                  let taf = try await TAF.from(string: rawText)
                  group.addTask {
                    let conditions = taf.groups.compactMap { Conditions(forecast: $0) }
                    return (taf.airportID, .init(conditions: conditions, raw: rawText))
                  }
                } catch {
                  Self.logger.warning(
                    "Failed to parse TAF from XML and text",
                    metadata: ["xmlError": "\(error)"]
                  )
                }
              } else {
                Self.logger.warning(
                  "Failed to parse TAF",
                  metadata: ["error": "\(error)"]
                )
              }
          }
        }

        return try await group.compactMap(\.self)
          .reduce(into: [:]) { result, pair in result[pair.0] = pair.1 }
      }

      forecasts = .value(newTAFs)
    } catch {
      // Don't update forecasts if cancelled
      guard !error.isNetworkCancellation else { return }
      Self.recordLoadFailure(error, dataType: "taf")
      forecasts = .error(error)
    }
  }

  func load(url: URL) async throws -> Data {
    Self.logger.info("Loading weather data from URL", metadata: ["url": "\(url)"])

    let (data, response) = try await session.data(from: url)
    if let response = response as? HTTPURLResponse {
      guard (200..<300).contains(response.statusCode) else {
        Self.logger.error(
          "Bad HTTP response",
          metadata: [
            "statusCode": "\(response.statusCode)",
            "url": "\(url)"
          ]
        )
        throw Errors.badResponse(response)
      }
    }

    guard !data.isEmpty else {
      Self.logger.error("Empty weather response", metadata: ["url": "\(url)"])
      throw Errors.emptyResponse(url: url)
    }

    Self.logger.info(
      "Downloaded weather data",
      metadata: [
        "size": "\(data.count)",
        "url": "\(url)"
      ]
    )

    return data
  }
}
