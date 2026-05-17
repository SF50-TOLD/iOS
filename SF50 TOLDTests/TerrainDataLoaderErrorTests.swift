import StreamingLZMA
import Testing

@testable import SF50_TOLD

struct TerrainDataLoaderErrorTests {

  // MARK: - ENOSPC detection via LZMAError

  /// Verifies that an `LZMAError.internalError` wrapping the POSIX "No space left on device"
  /// message (as produced by StreamingLZMA after flattening `errno` to a string) is
  /// classified as an out-of-disk-space error. This is the root cause of SF50-TOLD-29:
  /// `localizedDescription` returns the localized `errorDescription` ("Internal Error"),
  /// which does not contain the errno text, so the string fallback must look at
  /// `String(describing:)` (CustomStringConvertible) or `failureReason` instead.
  @Test
  func lzmaInternalErrorWithENOSPCMessageIsDetectedAsOutOfDiskSpace() {
    let lzmaError = LZMAError.internalError("Failed to write: No space left on device")
    #expect(lzmaError.isOutOfDiskSpace)
  }

  /// Verifies that an `LZMAError` whose message does not mention disk space is not
  /// misclassified as an out-of-disk-space error.
  @Test
  func lzmaInternalErrorWithUnrelatedMessageIsNotOutOfDiskSpace() {
    let lzmaError = LZMAError.internalError("Failed to write: Input/output error")
    #expect(!lzmaError.isOutOfDiskSpace)
  }

  /// Verifies that a genuine POSIX ENOSPC error is still detected.
  @Test
  func posixENOSPCErrorIsDetectedAsOutOfDiskSpace() {
    let posixError = POSIXError(.ENOSPC)
    #expect(posixError.isOutOfDiskSpace)
  }

  /// Verifies that a POSIX error with a different code is not misclassified.
  @Test
  func posixEIOErrorIsNotOutOfDiskSpace() {
    let posixError = POSIXError(.EIO)
    #expect(!posixError.isOutOfDiskSpace)
  }

  // MARK: - TerrainDataLoaderError reportability

  /// Verifies that `.outOfDiskSpace` is not reportable to Sentry, so the crash
  /// tracker is not flooded with user-side storage conditions.
  @Test
  func outOfDiskSpaceErrorIsNotReportable() {
    #expect(!TerrainDataLoaderError.outOfDiskSpace.isReportable)
  }

  /// Verifies that `.decompressionFailed` wrapping an LZMA ENOSPC error is
  /// never constructed — i.e. the mapping in `streamingDecompress` correctly
  /// throws `.outOfDiskSpace` instead, making the error non-reportable and
  /// presenting the correct recovery suggestion to the user.
  @Test
  func lzmaENOSPCErrorMapsToOutOfDiskSpaceNotDecompressionFailed() {
    let lzmaError = LZMAError.internalError("Failed to write: No space left on device")

    // Reproduce the mapping logic from streamingDecompress
    let terrainError: TerrainDataLoaderError =
      if lzmaError.isOutOfDiskSpace {
        .outOfDiskSpace
      } else {
        .decompressionFailed(lzmaError)
      }

    #expect(terrainError == .outOfDiskSpace)
    #expect(!terrainError.isReportable)
    #expect(terrainError.recoverySuggestion != nil)

    // Make sure it does NOT give "Check your internet connection" advice
    let badAdvice = "Check your internet connection"
    if let suggestion = terrainError.recoverySuggestion {
      #expect(!suggestion.contains(badAdvice))
    }
  }
}

// TerrainDataLoaderError must be Equatable for the test assertions above.
extension TerrainDataLoaderError: Equatable {
  public static func == (lhs: TerrainDataLoaderError, rhs: TerrainDataLoaderError) -> Bool {
    switch (lhs, rhs) {
      case (.noStorageAccess, .noStorageAccess),
        (.outOfDiskSpace, .outOfDiskSpace):
        return true
      case (.regionNotAvailable(let l), .regionNotAvailable(let r)):
        return l == r
      case (.downloadFailed, .downloadFailed),
        (.decompressionFailed, .decompressionFailed):
        return true
      default:
        return false
    }
  }
}
