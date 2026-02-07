import Foundation
import Logging
import SF50_Shared
import SwiftCIFP
import SwiftDOF
import SwiftNASR
import SwiftTimeZoneLookup

/// Errors that can occur during data processing.
enum NavDataProcessorError: LocalizedError {
  case missingCycleDates(source: String)

  var errorDescription: String? {
    String(localized: "Missing cycle dates")
  }

  var failureReason: String? {
    switch self {
      case .missingCycleDates(let source):
        String(localized: "Failed to determine cycle dates for \(source) data.")
    }
  }
}

/// Orchestrates the complete airport and obstacle data processing pipeline.
///
/// ``NavDataProcessor`` coordinates the loading, merging, and output of data from multiple sources:
///
/// 1. Initialize timezone lookup database
/// 2. Download and parse FAA NASR data using SwiftNASR
/// 3. Download and parse OurAirports CSV data
/// 4. Download and parse CIFP data for departure procedures
/// 5. Download and parse DOF obstacle data
/// 6. Merge datasets (NASR takes priority)
/// 7. Write to property list format
/// 8. Compress using LZMA
/// 9. Upload to GitHub (if token configured)
///
/// ## Progress Tracking
///
/// The processor reports progress through the ``onProgress`` callback with
/// 100 total units representing each major step.
///
/// ## See Also
///
/// - ``NASRProcessor``
/// - ``CIFPProcessor``
/// - ``DOFProcessor``
/// - ``OurAirportsLoader``
/// - ``GitHubUploader``
struct NavDataProcessor {
  /// The NASR cycle to download (e.g., 2501 for January 2025).
  let cycle: SwiftNASR.Cycle

  /// Directory where output files will be written.
  let outputLocation: URL

  /// Logger for status messages and errors.
  let logger: Logger

  /// Callback for progress updates (completed units out of 100, status message).
  var onProgress: (@MainActor @Sendable (_ completed: Int64, _ description: String) -> Void)?

  /// Callback invoked when GitHub upload fails (does not stop processing).
  var onUploadError: ((@MainActor @Sendable (_ error: NSError) -> Void))?

  /// Whether to skip uploading to GitHub.
  var skipUpload: Bool = false

  // MARK: - Main Processing Pipeline

  /// Executes the complete data processing pipeline.
  func process() async throws {
    // Load and merge all data (72 units)
    let loadedData = try await loadAndMergeAllData()

    // Build cycle information with effective/expiration dates
    guard let nasrEffective = cycle.effectiveDate,
      let nasrExpires = cycle.expirationDate
    else {
      throw NavDataProcessorError.missingCycleDates(source: "NASR")
    }

    var cifpInfo: AirportDataCodable.CycleInfo?
    if let cifpCycle = loadedData.cifpCycle {
      guard let effective = cifpCycle.effectiveDate,
        let expires = cifpCycle.expirationDate
      else {
        throw NavDataProcessorError.missingCycleDates(source: "CIFP")
      }
      cifpInfo = AirportDataCodable.CycleInfo(
        name: "\(cifpCycle)",
        effective: effective,
        expires: expires
      )
    }

    var dofInfo: AirportDataCodable.CycleInfo?
    if let dofCycle = loadedData.dofCycle {
      guard let effective = dofCycle.effectiveDate,
        let expires = dofCycle.expirationDate
      else {
        throw NavDataProcessorError.missingCycleDates(source: "DOF")
      }
      dofInfo = AirportDataCodable.CycleInfo(
        name: "\(dofCycle)",
        effective: effective,
        expires: expires
      )
    }

    let cycles = AirportDataCodable.DataCycles(
      nasr: AirportDataCodable.CycleInfo(
        name: "\(cycle)",
        effective: nasrEffective,
        expires: nasrExpires
      ),
      cifp: cifpInfo,
      dof: dofInfo
    )

    // Create combined codable data structure with airports, obstacles, and navaids
    let codableData = AirportDataCodable(
      cycles: cycles,
      ourAirportsLastUpdated: loadedData.ourAirportsLastUpdated,
      airports: loadedData.airports,
      obstacles: loadedData.obstacles,
      navaids: loadedData.navaids
    )

    // Write and compress combined data (19 units, cumulative: 91)
    let result = try writeAndCompressData(
      codableData,
      filename: "\(cycle)",
      dataDescription: "airport and obstacle"
    )
    await reportProgress(91, String(localized: "Compressing…"))

    try Task.checkCancellation()

    // Upload to GitHub (9 units, cumulative: 100)
    await uploadToGitHub(file: result.lzmaFile)
    await reportProgress(100, String(localized: "Complete!"))

    let airportCount = loadedData.airports.count
    let obstacleCount = loadedData.obstacles.count
    logger.notice("Complete - processed \(airportCount) airports and \(obstacleCount) obstacles")
  }

  // MARK: - Progress Reporting

  /// Reports progress via the callback.
  private func reportProgress(_ completed: Int64, _ description: String) async {
    if let onProgress {
      await onProgress(completed, description)
    }
  }

  // MARK: - Data Loading

  /// Loads all data sources and merges them into the final airport list.
  private func loadAndMergeAllData() async throws -> LoadedData {
    logger.notice("Initializing timezone lookup database…")
    await reportProgress(0, String(localized: "Initializing…"))
    let timezoneLookup = try SwiftTimeZoneLookup()

    try Task.checkCancellation()

    // Load NASR data (28 units, cumulative: 28)
    logger.notice("Loading NASR data for cycle \(cycle)…")
    await reportProgress(0, String(localized: "Loading NASR data…"))
    let nasrProcessor = NASRProcessor(logger: logger)
    let nasrAirports = try await nasrProcessor.loadNASRData(
      cycle: cycle,
      timezoneLookup: timezoneLookup
    ) { completed, total in
      // Map NASR progress (0-total) to overall progress (0-28)
      let mapped = Int64(Double(completed) / Double(total) * 28)
      await self.reportProgress(mapped, String(localized: "Loading NASR data…"))
    }

    try Task.checkCancellation()

    // Load OurAirports data (2 units, cumulative: 30)
    logger.notice("Loading OurAirports data…")
    await reportProgress(28, String(localized: "Loading OurAirports data…"))
    let ourAirportsLoader = OurAirportsLoader(logger: logger)
    let (ourAirports, ourAirportsLastUpdated) = try await ourAirportsLoader.loadAirports {
      completed,
      total in
      // Map OurAirports progress (0-total) to overall progress (28-30)
      let mapped = 28 + Int64(Double(completed) / Double(total) * 2)
      await self.reportProgress(mapped, String(localized: "Loading OurAirports data…"))
    }

    try Task.checkCancellation()

    // Load CIFP data (6 units, cumulative: 36)
    logger.notice("Loading CIFP data…")
    await reportProgress(30, String(localized: "Loading CIFP data…"))
    let cifpProcessor = CIFPProcessor(logger: logger)
    let cifpResult = try await cifpProcessor.loadCIFPData(cycle: cycle) { completed, total in
      // Map CIFP progress (0-total) to overall progress (30-36)
      let mapped = 30 + Int64(Double(completed) / Double(total) * 6)
      await self.reportProgress(mapped, String(localized: "Loading CIFP data…"))
    }
    await reportProgress(36, String(localized: "Loading CIFP data…"))

    try Task.checkCancellation()

    // Load DOF data (8 units, cumulative: 44)
    logger.notice("Loading DOF data…")
    await reportProgress(36, String(localized: "Loading DOF data…"))
    let dofProcessor = DOFProcessor(logger: logger)
    let dofResult = try await dofProcessor.loadDOFData { completed, total in
      // Map DOF progress (0-total) to overall progress (36-44)
      let mapped = 36 + Int64(Double(completed) / Double(total) * 8)
      await self.reportProgress(mapped, String(localized: "Loading DOF data…"))
    }
    await reportProgress(44, String(localized: "Loading DOF data…"))

    try Task.checkCancellation()

    // Merge and de-duplicate (28 units, cumulative: 72)
    logger.notice("Merging and de-duplicating airport data…")
    await reportProgress(44, String(localized: "Merging and de-duplicating airport data…"))
    let mergedAirports = await mergeAirports(
      NASRAirports: nasrAirports,
      ourAirports: ourAirports,
      timezoneLookup: timezoneLookup,
      cifpData: cifpResult.data,
      cifpProcessor: cifpProcessor
    )
    await reportProgress(72, String(localized: "Merging complete"))

    try Task.checkCancellation()

    // Extract DME-capable navaids from CIFP data
    let navaids: [NavaidCodable]?
    if let cifpData = cifpResult.data {
      navaids = await extractDMENavaids(from: cifpData)
    } else {
      navaids = nil
    }

    return LoadedData(
      airports: mergedAirports,
      ourAirportsLastUpdated: ourAirportsLastUpdated,
      cifpCycle: cifpResult.cycle,
      dofCycle: dofResult.cycle,
      obstacles: dofResult.obstacles,
      navaids: navaids
    )
  }

  // MARK: - File Output

  /// Writes data to plist and compresses with LZMA.
  private func writeAndCompressData<T: Encodable>(
    _ data: T,
    filename: String,
    dataDescription: String
  ) throws -> CompressedFileResult {
    logger.notice("Writing \(dataDescription) data to file…")

    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let encodedData = try encoder.encode(data)

    let plistFile = outputLocation.appendingPathComponent("\(filename).plist")
    if FileManager.default.fileExists(atPath: plistFile.path) {
      logger.warning("Overwriting existing file: \(plistFile.lastPathComponent)")
    }
    try encodedData.write(to: plistFile)

    logger.notice("Compressing \(dataDescription) data…")

    // swiftlint:disable:next legacy_objc_type
    let compressedData = try NSData(data: encodedData).compressed(using: .lzma)
    let lzmaFile = outputLocation.appendingPathComponent("\(filename).plist.lzma")
    if FileManager.default.fileExists(atPath: lzmaFile.path) {
      logger.warning("Overwriting existing file: \(lzmaFile.lastPathComponent)")
    }
    try compressedData.write(to: lzmaFile)

    return CompressedFileResult(lzmaFile: lzmaFile)
  }

  // MARK: - GitHub Upload

  /// Uploads file to GitHub if a token is configured.
  private func uploadToGitHub(file: URL) async {
    if skipUpload {
      logger.info("Skipping GitHub upload (skipUpload=true)")
      return
    }

    guard CredentialsConfig[.githubToken] != nil else {
      logger.info("GitHub token not configured, skipping upload")
      return
    }

    logger.notice("Uploading to GitHub…")
    await reportProgress(91, String(localized: "Uploading to GitHub…"))

    do {
      let uploader = GitHubUploader(logger: logger)

      // Upload combined data file
      try await uploader.uploadFile(
        filePath: file,
        targetPath: "3.0/\(cycle).plist.lzma",
        commitMessage: "Update airport and obstacle data for cycle \(cycle)"
      )
      logger.notice("Successfully uploaded data to GitHub")
    } catch {
      // Don't fail the entire process if upload fails
      logger.warning("GitHub upload failed: \(error.localizedDescription)")
      await onUploadError?(error as NSError)
    }
  }

  // MARK: - Airport Merging

  /// Merges NASR and OurAirports data, deduplicating by location ID.
  private func mergeAirports(
    NASRAirports: [AirportDataCodable.AirportCodable],
    ourAirports: [OurAirportData],
    timezoneLookup: SwiftTimeZoneLookup,
    cifpData: CIFPData?,
    cifpProcessor: CIFPProcessor
  ) async -> [AirportDataCodable.AirportCodable] {
    var mergedAirports = [AirportDataCodable.AirportCodable]()
    var NASRLocationIds = Set<String>()

    // Add all NASR airports first (they have priority)
    for airport in NASRAirports {
      // Add departure procedures from CIFP if available
      let departureProcedures: [AirportDataCodable.DepartureProcedureCodable]?
      if let cifpData, let icaoId = airport.ICAO_ID {
        let procedures = await cifpProcessor.extractDepartureProcedures(
          icaoId: icaoId,
          cifpData: cifpData
        )
        departureProcedures = procedures.isEmpty ? nil : procedures
      } else {
        departureProcedures = nil
      }

      // Add approach procedures from CIFP if available
      let approachProcedures: [AirportDataCodable.ApproachProcedureCodable]?
      if let cifpData, let icaoId = airport.ICAO_ID {
        let procedures = await cifpProcessor.extractApproachProcedures(
          icaoId: icaoId,
          cifpData: cifpData
        )
        approachProcedures = procedures.isEmpty ? nil : procedures
      } else {
        approachProcedures = nil
      }

      let airportWithDepartures = AirportDataCodable.AirportCodable(
        recordID: airport.recordID,
        locationID: airport.locationID,
        ICAO_ID: airport.ICAO_ID,
        name: airport.name,
        city: airport.city,
        dataSource: airport.dataSource,
        latitude: airport.latitude,
        longitude: airport.longitude,
        elevation: airport.elevation,
        variation: airport.variation,
        timeZone: airport.timeZone,
        runways: airport.runways,
        departureProcedures: departureProcedures,
        approachProcedures: approachProcedures
      )

      mergedAirports.append(airportWithDepartures)
      NASRLocationIds.insert(airport.locationID)
    }

    // Add OurAirports data that doesn't exist in NASR
    var ourAirportsAdded = 0
    for ourAirport in ourAirports {
      // Skip if this airport's local_id matches a NASR locationID
      if !ourAirport.localId.isEmpty && NASRLocationIds.contains(ourAirport.localId) {
        continue
      }

      // Convert OurAirports data to our codable format
      var runways = [AirportDataCodable.RunwayCodable]()
      for runway in ourAirport.runways {
        let takeoffRun = runway.lengthFt - runway.displacedThresholdFt

        runways.append(
          AirportDataCodable.RunwayCodable(
            name: runway.name,
            elevation: runway.elevationFt.map { $0 * 0.3048 },  // Convert feet to meters
            trueHeading: runway.trueHeading,
            gradient: nil,  // OurAirports doesn't provide gradient
            length: runway.lengthFt * 0.3048,  // Convert feet to meters
            takeoffRun: takeoffRun > 0 ? takeoffRun * 0.3048 : nil,
            takeoffDistance: nil,  // Not available in OurAirports
            landingDistance: nil,  // Not available in OurAirports
            isTurf: runway.isTurf,
            reciprocalName: runway.reciprocalName,
            thresholdLatitude: runway.thresholdLatitude,
            thresholdLongitude: runway.thresholdLongitude,
            width: runway.widthFt.map { $0 * 0.3048 },  // Convert feet to meters
            thresholdCrossingHeight: nil,  // Not available in OurAirports
            glidepathAngle: nil,  // Not available in OurAirports
            displacedThresholdDistance: runway.displacedThresholdFt > 0
              ? runway.displacedThresholdFt * 0.3048 : nil
          )
        )
      }

      if runways.isEmpty { continue }

      // Calculate magnetic variation for this location
      let variation = GeoCalculations.calculateMagneticVariation(
        ourAirport.latitude,
        ourAirport.longitude
      )

      // Lookup timezone for this airport
      let timeZone = timezoneLookup.simple(
        latitude: Float(ourAirport.latitude),
        longitude: Float(ourAirport.longitude)
      )

      // Add departure procedures from CIFP if available (OurAirports may have ICAO IDs too)
      let departureProcedures: [AirportDataCodable.DepartureProcedureCodable]?
      if let cifpData, let icaoId = ourAirport.ICAO_ID {
        let procedures = await cifpProcessor.extractDepartureProcedures(
          icaoId: icaoId,
          cifpData: cifpData
        )
        departureProcedures = procedures.isEmpty ? nil : procedures
      } else {
        departureProcedures = nil
      }

      // Add approach procedures from CIFP if available (OurAirports may have ICAO IDs too)
      let approachProcedures: [AirportDataCodable.ApproachProcedureCodable]?
      if let cifpData, let icaoId = ourAirport.ICAO_ID {
        let procedures = await cifpProcessor.extractApproachProcedures(
          icaoId: icaoId,
          cifpData: cifpData
        )
        approachProcedures = procedures.isEmpty ? nil : procedures
      } else {
        approachProcedures = nil
      }

      let codableAirport = AirportDataCodable.AirportCodable(
        recordID: ourAirport.id,
        locationID: ourAirport.localId,
        ICAO_ID: ourAirport.ICAO_ID,
        name: ourAirport.name,
        city: ourAirport.municipality,
        dataSource: "ourAirports",
        latitude: ourAirport.latitude,
        longitude: ourAirport.longitude,
        elevation: ourAirport.elevationFt * 0.3048,  // Convert feet to meters
        variation: variation,
        timeZone: timeZone,
        runways: runways,
        departureProcedures: departureProcedures,
        approachProcedures: approachProcedures
      )

      mergedAirports.append(codableAirport)
      ourAirportsAdded += 1
    }

    logger.notice("Added \(ourAirportsAdded) airports from OurAirports (non-duplicates)")
    logger.notice("Total airports after merge: \(mergedAirports.count)")

    return mergedAirports
  }

  // MARK: - Navaid Extraction

  /// Extracts DME-capable navaids from CIFP data.
  private func extractDMENavaids(from cifpData: CIFPData) async -> [NavaidCodable] {
    let vhfNavaids = await cifpData.vhfNavaids
    var navaids = [NavaidCodable]()

    for (_, navaid) in vhfNavaids {
      guard navaid.hasDME else { continue }

      // Prefer DME transponder coordinate, fall back to VOR
      guard let coordinate = navaid.dmeCoordinate ?? navaid.vorCoordinate else { continue }

      let navaidCodable = NavaidCodable(
        identifier: navaid.identifier,
        icaoRegion: navaid.icaoRegion,
        type: navaid.navaidClass.description,
        latitude: coordinate.latitudeDeg,
        longitude: coordinate.longitudeDeg,
        elevationFt: navaid.dmeElevationFt.map { Double($0) }
      )
      navaids.append(navaidCodable)
    }

    logger.notice("Extracted \(navaids.count) DME-capable navaids from CIFP data")
    return navaids
  }

  // MARK: - Nested Types

  /// Container for all loaded data sources.
  private struct LoadedData {
    let airports: [AirportDataCodable.AirportCodable]
    let ourAirportsLastUpdated: Date?
    let cifpCycle: SwiftCIFP.Cycle?
    let dofCycle: SwiftDOF.Cycle?
    let obstacles: [AirportDataCodable.ObstacleCodable]
    let navaids: [NavaidCodable]?
  }

  /// Result of writing and compressing a data file.
  private struct CompressedFileResult {
    let lzmaFile: URL
  }
}
