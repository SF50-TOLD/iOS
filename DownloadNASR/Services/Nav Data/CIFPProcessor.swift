import Foundation
import Logging
import SF50_Shared
import SwiftCIFP
import SwiftNASR
import ZIPFoundation

/// Processes FAA CIFP (Coded Instrument Flight Procedures) data.
///
/// ``CIFPProcessor`` handles downloading and parsing FAA CIFP data using SwiftCIFP,
/// converting it to the application's codable format.
///
/// ## See Also
///
/// - ``DataProcessor`` - The orchestrator that uses this processor
/// - ``NASRProcessor`` - Processes NASR airport data
/// - ``DOFProcessor`` - Processes DOF obstacle data
struct CIFPProcessor {
  /// Path terminators that indicate a plottable SID leg.
  private static let plottablePathTerminators: Set<PathTerminator> = [
    .initialFix,  // IF
    .trackToFix,  // TF
    .courseToFix,  // CF
    .directToFix,  // DF
    .radiusToFix,  // RF
    .arcToFix  // AF
  ]

  // Progress allocation within CIFP processing (out of 100):
  // - Download: 0-30
  // - Parse: 30-90
  // - Link: 90-100
  private static let downloadProgressEnd = 30
  private static let parseProgressEnd = 90
  private static let linkProgressEnd = 100

  /// Logger for status messages and errors.
  let logger: Logger

  /// Downloads and parses CIFP data for the specified cycle.
  /// - Parameters:
  ///   - cycle: The NASR cycle to download CIFP data for.
  ///   - onProgress: Callback for progress updates (completed, total).
  /// - Returns: A `CIFPResult` containing the parsed data and cycle.
  func loadCIFPData(
    cycle: SwiftNASR.Cycle,
    onProgress: (@Sendable (Int, Int) async -> Void)? = nil
  ) async throws -> CIFPResult {
    await onProgress?(0, 100)

    // CIFP data is available from the FAA at this URL pattern
    // Format: CIFP_YYMMDD.zip (e.g., CIFP_250102.zip for January 2, 2025)
    let dateString = formatCIFPDate(cycle)
    let cifpURLString = "https://aeronav.faa.gov/Upload_313-d/cifp/CIFP_\(dateString).zip"
    guard let cifpURL = URL(string: cifpURLString) else {
      throw CIFPProcessorError.invalidURL(cifpURLString)
    }

    logger.notice("Downloading CIFP data from \(cifpURL)…")

    // Download the ZIP file
    let (downloadedData, response) = try await URLSession.shared.data(from: cifpURL)
    await onProgress?(Self.downloadProgressEnd, 100)

    if let httpResponse = response as? HTTPURLResponse,
      !(200..<300).contains(httpResponse.statusCode)
    {
      throw CIFPProcessorError.downloadFailed(httpResponse.statusCode)
    }

    try Task.checkCancellation()

    // Extract CIFP data from ZIP
    let cifpData = try extractCIFPFromZip(downloadedData)

    // Parse CIFP
    logger.notice("Parsing CIFP data…")
    let cifp = try CIFP(
      data: cifpData,
      progressHandler: { progress in
        self.observeProgress(
          progress,
          mappingTo: Self.downloadProgressEnd..<Self.parseProgressEnd,
          onProgress: onProgress
        )
      },
      errorCallback: { error, lineNumber in
        if let lineNumber {
          self.logger.debug("CIFP parse error at line \(lineNumber): \(error)")
        } else {
          self.logger.debug("CIFP parse error: \(error)")
        }
      }
    )
    await onProgress?(Self.parseProgressEnd, 100)

    try Task.checkCancellation()

    // Create linked data for fix resolution
    logger.notice("Linking CIFP data…")
    let linked = await cifp.linked()
    await onProgress?(Self.linkProgressEnd, 100)

    let airportCount = await linked.airports.count
    logger.notice("Loaded CIFP data with \(airportCount) airports for cycle \(cifp.cycle)")
    return CIFPResult(cycle: cifp.cycle, data: linked)
  }

  /// Sets up KVO observation on a Progress object and maps updates to the target range.
  /// - Parameters:
  ///   - progress: The Progress object from SwiftCIFP to observe.
  ///   - range: The range to map progress to (e.g., 30..<90 means 30-90%).
  ///   - onProgress: Callback to report progress.
  private func observeProgress(
    _ progress: Progress,
    mappingTo range: Range<Int>,
    onProgress: (@Sendable (Int, Int) async -> Void)?
  ) {
    guard let onProgress else { return }

    let rangeSize = range.upperBound - range.lowerBound

    // Set up KVO observation on the progress
    // Note: Don't use .initial option to avoid synchronous callback during setup
    let observation = progress.observe(\.fractionCompleted, options: [.new]) { progress, _ in
      let fraction = progress.fractionCompleted
      let mapped = range.lowerBound + Int(Double(rangeSize) * fraction)
      Task.detached {
        await onProgress(mapped, 100)
      }
    }

    // Store observation to keep it alive for the duration of the async operation
    Task { await ProgressObservationHolder.shared.add(observation) }
  }

  /// Extracts the CIFP file from the downloaded ZIP archive.
  private func extractCIFPFromZip(_ zipData: Data) throws -> Data {
    let archive = try Archive(data: zipData, accessMode: .read)

    guard let entry = archive.first(where: { $0.path.hasPrefix("FAACIFP") }) else {
      throw CIFPProcessorError.cifpFileNotFound
    }

    var cifpData = Data()
    _ = try archive.extract(entry) { cifpData.append($0) }
    return cifpData
  }

  /// Formats NASR cycle date for CIFP URL (YYMMDD format).
  private func formatCIFPDate(_ cycle: SwiftNASR.Cycle) -> String {
    let yearSuffix = cycle.year % 100
    return String(format: "%02d%02d%02d", yearSuffix, cycle.month, cycle.day)
  }

  /// Extracts departure procedures for an airport from CIFP data.
  /// - Parameters:
  ///   - icaoId: The ICAO identifier of the airport.
  ///   - cifpData: The parsed CIFP linked data.
  /// - Returns: Array of departure procedures for the airport.
  func extractDepartureProcedures(
    icaoId: String,
    cifpData: CIFPData
  ) async -> [AirportDataCodable.DepartureProcedureCodable] {
    guard let cifpAirport = await cifpData.airports[icaoId] else {
      return []
    }

    var procedures = [AirportDataCodable.DepartureProcedureCodable]()
    var processedIdentifiers = Set<String>()

    for sid in cifpAirport.sids {
      // Skip if we've already processed this SID identifier (avoid duplicates from transitions)
      guard !processedIdentifiers.contains(sid.identifier) else { continue }
      processedIdentifiers.insert(sid.identifier)

      // Check if all legs are plottable
      let isPlottable = sid.legs.allSatisfy { leg in
        guard let pathTerminator = leg.pathTerminator else { return false }
        return Self.plottablePathTerminators.contains(pathTerminator)
      }

      // Extract fixes and calculate gradient if plottable
      var fixes: [AirportDataCodable.FixCodable]?
      var requiredGradient: Double?
      if isPlottable {
        let (extractedFixes, gradient) = await extractFixesAndGradient(sid: sid, cifpData: cifpData)
        if !extractedFixes.isEmpty {
          fixes = extractedFixes
        }
        requiredGradient = gradient
      }

      let procedure = AirportDataCodable.DepartureProcedureCodable(
        identifier: sid.identifier,
        runwayNames: Array(sid.runwayNames).sorted(),
        fixes: fixes,
        requiredClimbGradientFtPerNM: requiredGradient
      )
      procedures.append(procedure)
    }

    return procedures.sorted { $0.identifier < $1.identifier }
  }

  /// Extracts fixes and calculates climb gradient for a SID.
  private func extractFixesAndGradient(
    sid: SID,
    cifpData _: CIFPData
  ) async -> (fixes: [AirportDataCodable.FixCodable], gradient: Double?) {
    var fixes = [AirportDataCodable.FixCodable]()
    var maxGradient: Double?
    var previousLatitude: Double?
    var previousLongitude: Double?
    var previousAltitude: Int?

    for leg in sid.legs.sorted() {
      // Get fix coordinate
      let fix = await leg.fix
      guard let coordinate = fix?.coordinate,
        let fixIdentifier = fix?.identifier
      else {
        continue
      }

      let currentLat = coordinate.latitudeDeg
      let currentLon = coordinate.longitudeDeg

      // Convert altitude constraint
      let altitudeRestriction = leg.altitudeConstraint.flatMap {
        convertAltitudeConstraint($0)
      }

      // Add fix to list
      let fixCodable = AirportDataCodable.FixCodable(
        identifier: fixIdentifier,
        latitude: currentLat,
        longitude: currentLon,
        altitudeRestriction: altitudeRestriction
      )
      fixes.append(fixCodable)

      // Calculate gradient if we have altitude data
      if let altitudeConstraint = leg.altitudeConstraint,
        let currentAltitude = extractMinAltitudeFeet(from: altitudeConstraint),
        let prevLat = previousLatitude,
        let prevLon = previousLongitude,
        let prevAlt = previousAltitude
      {
        let distanceNM = GeoCalculations.calculateDistanceNM(
          fromLat: prevLat,
          fromLon: prevLon,
          toLat: currentLat,
          toLon: currentLon
        )

        if distanceNM > 0.1 {
          let altitudeGainFt = Double(currentAltitude - prevAlt)
          let gradient = altitudeGainFt / distanceNM

          if gradient > 0 {
            maxGradient = max(maxGradient ?? 0, gradient)
          }
        }

        previousAltitude = currentAltitude
      } else if let altitudeConstraint = leg.altitudeConstraint,
        let altitude = extractMinAltitudeFeet(from: altitudeConstraint)
      {
        previousAltitude = altitude
      }

      previousLatitude = currentLat
      previousLongitude = currentLon
    }

    return (fixes, maxGradient)
  }

  /// Converts a SwiftCIFP altitude constraint to our codable representation.
  private func convertAltitudeConstraint(
    _ constraint: AltitudeConstraint
  ) -> AirportDataCodable.AltitudeRestrictionCodable? {
    switch constraint {
      case .at(let altitude):
        guard let feet = altitude.feetValue else { return nil }
        return .at(feet)

      case .atOrAbove(let altitude):
        guard let feet = altitude.feetValue else { return nil }
        return .atOrAbove(feet)

      case .atOrBelow(let altitude):
        guard let feet = altitude.feetValue else { return nil }
        return .atOrBelow(feet)

      case .between(let lower, let upper),
        .atOrAboveToAtOrBelow(let lower, let upper),
        .atOrAboveToAt(let lower, let upper),
        .atToAtOrBelow(let lower, let upper),
        .atToAtOrAbove(let lower, let upper),
        .atOrBelowToAtOrAbove(let lower, let upper):
        guard let minFeet = lower.feetValue, let maxFeet = upper.feetValue else { return nil }
        return .between(min: minFeet, max: maxFeet)

      case .glideSlopeIntercept, .glidePathIntercept:
        // These are approach-specific, not relevant for departure procedures
        return nil
    }
  }

  /// Extracts the minimum altitude value in feet from an altitude constraint (for gradient calculation).
  private func extractMinAltitudeFeet(from constraint: AltitudeConstraint) -> Int? {
    switch constraint {
      case .at(let altitude),
        .atOrAbove(let altitude),
        .atOrBelow(let altitude),
        .glideSlopeIntercept(let altitude),
        .glidePathIntercept(let altitude):
        return altitude.feetValue

      case .between(let lower, _),
        .atOrAboveToAtOrBelow(let lower, _),
        .atOrAboveToAt(let lower, _),
        .atToAtOrBelow(let lower, _),
        .atToAtOrAbove(let lower, _),
        .atOrBelowToAtOrAbove(let lower, _):
        return lower.feetValue
    }
  }

  // MARK: - Nested Types

  /// Result container for CIFP loading.
  struct CIFPResult {
    let cycle: SwiftCIFP.Cycle?
    let data: CIFPData?
  }
}

/// Errors that can occur during CIFP processing.
enum CIFPProcessorError: LocalizedError {
  case invalidURL(String)
  case downloadFailed(Int)
  case cifpFileNotFound

  var errorDescription: String? {
    String(localized: "FAA CIFP data could not be processed.")
  }

  var failureReason: String? {
    switch self {
      case .invalidURL(let url):
        String(localized: "The URL “\(url)” is invalid.")
      case .downloadFailed(let statusCode):
        String(localized: "Download failed with HTTP status \(statusCode).")
      case .cifpFileNotFound:
        String(localized: "FAACIFP file not found in downloaded archive.")
    }
  }
}
