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
///
/// Output is written to the app's Documents directory.
enum NavDataHeadlessProcessor {
  private static let env = ProcessInfo.processInfo.environment

  /// Returns true if headless mode is enabled via environment variable.
  static func shouldRunHeadless() -> Bool {
    env["NASR_HEADLESS"] == "1"
  }

  /// Runs the NASR processor in headless mode.
  /// - Returns: Exit code (0 for success, 1 for error)
  static func run() async -> Int32 {
    let logger = Logger(label: "codes.tim.DownloadNASR")

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
