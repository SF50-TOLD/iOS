import Foundation
import Logging
import SwiftNASR

/// Handles headless/automated execution of the NASR processor via environment variables.
///
/// Environment variables:
/// - `NASR_HEADLESS`: Set to "1" to enable headless mode
/// - `NASR_CYCLE`: Cycle to download ("current", "next", or "YYYY-MM-DD")
/// - `NASR_OUTPUT`: Output directory path
/// - `NASR_SKIP_UPLOAD`: Set to "1" to skip GitHub upload
enum HeadlessProcessor {
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

    // Parse and validate NASR_OUTPUT
    guard let outputPath = env["NASR_OUTPUT"] else {
      logger.error("NASR_OUTPUT environment variable is required")
      return 1
    }

    // Parse cycle
    let cycle: Cycle
    switch cycleString.lowercased() {
      case "current":
        cycle = .current
      case "next":
        guard let nextCycle = Cycle.current.next else {
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

    // Validate output directory exists
    let outputURL = URL(fileURLWithPath: outputPath)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: outputPath, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      logger.error("Output path does not exist or is not a directory: \(outputPath)")
      return 1
    }

    logger.info("Starting headless processing for cycle \(cycle) to \(outputPath)")

    // Run processor
    var processor = DataProcessor(
      cycle: cycle,
      outputLocation: outputURL,
      logger: logger
    )
    processor.skipUpload = env["NASR_SKIP_UPLOAD"] == "1"

    // For headless mode, just log progress
    processor.onProgress = { completed, description in
      logger.info("Progress: \(completed)/100 - \(description)")
    }

    do {
      try await processor.process()
      logger.info("Processing complete. Output saved to: \(outputPath)")
      return 0
    } catch {
      logger.error("Processing failed: \(error)")
      return 1
    }
  }
}
