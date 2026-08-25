import Foundation
import Logging
import SF50_Shared

/// Handles headless/automated execution of the terrain processor via environment variables.
///
/// Environment variables:
/// - `TERRAIN_HEADLESS`: Set to "1" to enable terrain headless mode
/// - `TERRAIN_REGIONS`: Regions to process ("na,eu,as" or "all", default: all)
/// - `TERRAIN_SKIP_UPLOAD`: Set to "1" to skip R2 upload
///
/// Output is written to the app's Documents directory.
enum TerrainHeadlessProcessor {
  private static let env = ProcessInfo.processInfo.environment

  /// Returns true if terrain headless mode is enabled via environment variable.
  static func shouldRunHeadless() -> Bool {
    env["TERRAIN_HEADLESS"] == "1"
  }

  // MARK: - Main Entry Point

  /// Runs the terrain processor in headless mode.
  /// - Returns: Exit code (0 for success, 1 for error)
  static func run() async -> Int32 {
    let logger = Logger(label: "TerrainHeadlessProcessor")

    // Use app's Documents directory
    guard
      let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first
    else {
      logger.error("Could not locate Documents directory")
      return 1
    }

    let outputURL = documentsURL.appendingPathComponent("Terrain", isDirectory: true)

    // Create output directory if needed
    do {
      try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
    } catch {
      logger.error("Failed to create output directory: \(error.localizedDescription)")
      return 1
    }

    // Parse regions
    let regions: [TerrainRegion]
    if let regionString = env["TERRAIN_REGIONS"], regionString.lowercased() != "all" {
      let codes = regionString.split(separator: ",").map {
        String($0).trimmingCharacters(in: .whitespaces)
      }
      regions = codes.compactMap { code in
        TerrainRegion.allCases.first { $0.rawValue == code }
      }
      if regions.isEmpty {
        let validCodes = TerrainRegion.allCases.map(\.rawValue).joined(separator: ", ")
        logger.error("No valid regions. Valid codes: \(validCodes)")
        return 1
      }
    } else {
      regions = Array(TerrainRegion.allCases)
    }

    logger.notice(
      "Processing \(regions.count) region(s): \(regions.map(\.rawValue).joined(separator: ", "))"
    )

    // Create processor
    let processor = SRTMProcessor(
      regions: regions,
      outputLocation: outputURL,
      logger: logger
    )

    if env["TERRAIN_SKIP_UPLOAD"] == "1" {
      await processor.setSkipUpload(true)
    }

    // Create progress callback for console logging
    let onProgress: @MainActor @Sendable (TerrainProgress) -> Void = { state in
      logProgress(state, logger: logger)
    }

    // Set callbacks
    await processor.setCallbacks(
      onProgress: onProgress,
      onUploadError: nil,
      onLog: nil
    )

    do {
      try await processor.process()
      logger.notice("Terrain processing complete")
      return 0
    } catch {
      logger.error("Processing failed: \(error.localizedDescription)")
      return 1
    }
  }

  /// Logs progress state changes to the console.
  private static func logProgress(_ state: TerrainProgress, logger: Logger) {
    switch state {
      case .pending:
        break
      case .downloading(let region, let completed, let total):
        logger.notice("Downloading \(region.displayName): \(completed) of \(total)")
      case .parsing(let region, let completed, let total):
        logger.notice("Parsing \(region.displayName): \(completed) of \(total)")
      case .generatingManifest:
        logger.notice("Generating manifest…")
      case .uploading(let region, let fraction):
        logger.notice("Uploading \(region.displayName): \(Int(fraction * 100))%")
      case .uploadingManifest:
        logger.notice("Uploading manifest…")
      case .completed:
        logger.notice("Processing completed")
      case .cancelled:
        logger.warning("Processing cancelled")
      case .failed(let error):
        logger.error("Processing failed: \(error.localizedDescription)")
    }
  }
}
