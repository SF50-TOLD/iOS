import Foundation

/// Efficiently writes binary data to a file or memory buffer using streaming I/O.
///
/// `BinaryFileWriter` avoids intermediate `Data` allocations by writing directly
/// to an `OutputStream`. It provides type-safe methods for writing integers and
/// raw bytes with explicit endianness control.
///
/// ## Usage
///
/// ```swift
/// // Write directly to a file
/// try BinaryFileWriter.write(to: fileURL) { writer in
///     writer.writeBytes([0x53, 0x52, 0x54, 0x4D])  // magic
///     writer.writeUInt16(2)                         // version
///     writer.writeInt16(-100)                       // signed value
///     writer.writeData(elevationData)               // raw data
/// }
///
/// // Build in-memory Data
/// let data = try BinaryFileWriter.buildData { writer in
///     writer.writeUInt32(count)
///     writer.writeBytes(payload)
/// }
/// ```
final class BinaryFileWriter {

  private let stream: OutputStream

  /// Creates a writer that writes to the given output stream.
  private init(stream: OutputStream) {
    self.stream = stream
    stream.open()
  }

  // MARK: - Factory Methods

  /// Builds binary data in memory using the provided closure.
  ///
  /// - Parameter block: A closure that receives the writer and performs write operations.
  /// - Returns: The accumulated binary data.
  /// - Throws: `BinaryFileWriterError` if writing fails.
  static func buildData(_ block: (BinaryFileWriter) throws -> Void) throws -> Data {
    let stream = OutputStream.toMemory()
    let writer = BinaryFileWriter(stream: stream)
    try block(writer)
    writer.stream.close()

    guard let data = stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data else {
      throw BinaryFileWriterError.memoryStreamFailed
    }
    return data
  }

  // MARK: - Write Methods

  /// Writes an array of bytes.
  func writeBytes(_ bytes: [UInt8]) {
    bytes.withUnsafeBufferPointer { buffer in
      guard let baseAddress = buffer.baseAddress else { return }
      stream.write(baseAddress, maxLength: bytes.count)
    }
  }

  // MARK: - Integer Write Methods (Little Endian)

  /// Writes a 16-bit unsigned integer in little-endian byte order.
  func writeUInt16(_ value: UInt16) {
    _ = withUnsafeBytes(of: value.littleEndian) { buffer in
      stream.write(buffer.baseAddress!.assumingMemoryBound(to: UInt8.self), maxLength: 2)
    }
  }

  /// Writes a 16-bit signed integer in little-endian byte order.
  func writeInt16(_ value: Int16) {
    _ = withUnsafeBytes(of: value.littleEndian) { buffer in
      stream.write(buffer.baseAddress!.assumingMemoryBound(to: UInt8.self), maxLength: 2)
    }
  }

  /// Writes a 32-bit unsigned integer in little-endian byte order.
  func writeUInt32(_ value: UInt32) {
    _ = withUnsafeBytes(of: value.littleEndian) { buffer in
      stream.write(buffer.baseAddress!.assumingMemoryBound(to: UInt8.self), maxLength: 4)
    }
  }

  /// Writes a 64-bit unsigned integer in little-endian byte order.
  func writeUInt64(_ value: UInt64) {
    _ = withUnsafeBytes(of: value.littleEndian) { buffer in
      stream.write(buffer.baseAddress!.assumingMemoryBound(to: UInt8.self), maxLength: 8)
    }
  }

  deinit {
    stream.close()
  }
}

// MARK: - Errors

enum BinaryFileWriterError: LocalizedError {
  case cannotOpenFile(URL)
  case memoryStreamFailed

  var errorDescription: String? {
    switch self {
      case .cannotOpenFile(let url):
        return "Cannot open file for writing: \(url.path)"
      case .memoryStreamFailed:
        return "Failed to retrieve data from memory stream"
    }
  }
}
