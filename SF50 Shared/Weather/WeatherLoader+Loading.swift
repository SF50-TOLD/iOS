import Foundation
import Gzip
import Sentry
import SwiftMETAR

extension WeatherLoader {
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
          let prefix = data.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " ")
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
    } catch is CancellationError {
      // Don't update observations if cancelled
    } catch {
      SentrySDK.capture(error: error) { scope in
        scope.setLevel(.warning)
        scope.setTag(value: "metar", key: "weather.dataType")
        scope.setFingerprint(["weather-loading", "metar"])
      }
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
          let prefix = data.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " ")
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
    } catch is CancellationError {
      // Don't update forecasts if cancelled
    } catch {
      SentrySDK.capture(error: error) { scope in
        scope.setLevel(.warning)
        scope.setTag(value: "taf", key: "weather.dataType")
        scope.setFingerprint(["weather-loading", "taf"])
      }
      forecasts = .error(error)
    }
  }

  func loadWindsAloft() async {
    windsAloft = .loading
    await notifySubscribers()

    do {
      try Task.checkCancellation()
      let data = try await load(url: Self.windsAloftURL)
      try Task.checkCancellation()

      guard let text = String(data: data, encoding: .utf8) else {
        Self.logger.error("Failed to decode winds aloft data as UTF-8")
        windsAloft = .error(Errors.invalidTextEncoding(url: Self.windsAloftURL))
        return
      }

      let parsed = try await WindsAloft.from(string: text)
      let stationData = parsed.stations.reduce(into: [String: WindsAloftData]()) {
        result,
        station in
        result[station.id] = WindsAloftData(from: station)
      }

      Self.logger.info(
        "Loaded winds aloft data",
        metadata: ["stationCount": "\(stationData.count)"]
      )

      windsAloft = .value(stationData)
    } catch is CancellationError {
      // Don't update windsAloft if cancelled
    } catch {
      SentrySDK.capture(error: error) { scope in
        scope.setLevel(.warning)
        scope.setTag(value: "windsAloft", key: "weather.dataType")
        scope.setFingerprint(["weather-loading", "windsAloft"])
      }
      Self.logger.error(
        "Failed to load winds aloft",
        metadata: ["error": "\(error)"]
      )
      windsAloft = .error(error)
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
