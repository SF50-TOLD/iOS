import Foundation
import Logging
import NavDataGeneration
import SwiftNASR

/// Handles headless/automated execution of the NASR processor via environment variables.
///
/// Environment variables:
/// - `NASR_HEADLESS`: Set to "1" to enable headless mode
/// - `NASR_CYCLE`: Cycle to download ("current", "next", or "YYYY-MM-DD")
/// - `NASR_SKIP_UPLOAD`: Set to "1" to skip GitHub upload
/// - `NASR_BUILD_STORE_FROM`: Path to an already-published `<cycle>.plist`. Builds the SwiftData
///   store and its manifest from that dataset instead of downloading anything, and exits.
/// - `NASR_STORE_OUTPUT`: Where to write the store and manifest. Defaults to the plist's directory.
/// - `NASR_PUBLISH_STORE`: Set to "1" to upload the built store and manifest to R2.
///
/// Output is written to the app's Documents directory.
enum NavDataHeadlessProcessor {
  private static let env = ProcessInfo.processInfo.environment

  /// Returns true if headless mode is enabled via environment variable.
  static func shouldRunHeadless() -> Bool {
    env["NASR_HEADLESS"] == "1"
  }

  /// Builds the prebuilt store for a dataset that has already been published.
  ///
  /// - Parameters:
  ///   - plistPath: The `<cycle>.plist` to build from.
  ///   - logger: Where to report progress.
  /// - Returns: An exit code.
  private static func buildStore(fromPlistAt plistPath: String, logger: Logger) async -> Int32 {
    let plist = URL(filePath: plistPath)
    let cycle = plist.deletingPathExtension().lastPathComponent
    let outputLocation =
      env["NASR_STORE_OUTPUT"].map { URL(filePath: $0) }
      ?? plist.deletingLastPathComponent()

    do {
      try FileManager.default.createDirectory(at: outputLocation, withIntermediateDirectories: true)
      let output = try await NavDataStoreBuilder(logger: logger)
        .build(fromPlistAt: plist, cycle: cycle, outputLocation: outputLocation)
      logger.notice("Wrote \(output.store.path) and \(output.manifest.path)")

      if env["NASR_PUBLISH_STORE"] == "1" {
        try await NavDataStoreUploader(logger: logger).upload(output, cycle: cycle)
      }
      return 0
    } catch {
      logger.error("Couldn’t build the store: \(error)")
      return 1
    }
  }

  /// Runs the NASR processor in headless mode.
  /// - Returns: Exit code (0 for success, 1 for error)
  static func run() async -> Int32 {
    let logger = Logger(label: "codes.tim.DownloadNASR")

    // Building a store transcodes a dataset that has already been published, rather than going back
    // to the FAA for it: the store is then a pure function of the payload the app falls back to,
    // and cannot drift from it.
    if let plistPath = env["NASR_BUILD_STORE_FROM"] {
      return await buildStore(fromPlistAt: plistPath, logger: logger)
    }

    // Parse and validate NASR_CYCLE
    guard let cycleString = env["NASR_CYCLE"] else {
      logger.error("NASR_CYCLE environment variable is required")
      return 1
    }

    // Parse cycle
    let cycle: Cycle
    switch cycleString.lowercased() {
      case "current":
        cycle = .effective
      case "next":
        guard let nextCycle = Cycle.effective.next else {
          logger.error("Could not determine next cycle")
          return 1
        }
        cycle = nextCycle
      default:
        // Parse YYYY-MM-DD format
        let parts = cycleString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
          let year = UInt(exactly: parts[0]),
          let month = UInt8(exactly: parts[1]),
          let day = UInt8(exactly: parts[2])
        else {
          logger.error(
            "Invalid cycle format '\(cycleString)'. Use 'current', 'next', or 'YYYY-MM-DD'"
          )
          return 1
        }
        cycle = Cycle(year: year, month: month, day: day)
    }

    // Use app's Documents directory
    guard
      let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first
    else {
      logger.error("Could not locate Documents directory")
      return 1
    }

    let outputURL = documentsURL.appendingPathComponent("NavData", isDirectory: true)

    // Create output directory if needed
    do {
      try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
    } catch {
      logger.error("Failed to create output directory: \(error.localizedDescription)")
      return 1
    }

    logger.notice("Starting headless processing for cycle \(cycle) to \(outputURL.path)")

    // Run processor
    var processor = NavDataProcessor(
      cycle: cycle,
      outputLocation: outputURL,
      logger: logger
    )

    // For headless mode, just log progress
    processor.onProgress = { completed, description in
      logger.info("Progress: \(completed)/100 - \(description)")
    }

    let skipUpload = env["NASR_SKIP_UPLOAD"] == "1"

    do {
      let file = try await processor.process()
      if !skipUpload,
        let uploadError = await NavDataUploader(cycle: cycle, logger: logger).upload(file: file)
      {
        logger.warning("GitHub upload failed: \(uploadError.localizedDescription)")
      }
      logger.notice("Processing complete. Output saved to: \(outputURL.path)")
      return 0
    } catch {
      logger.error("Processing failed: \(error)")
      return 1
    }
  }
}
