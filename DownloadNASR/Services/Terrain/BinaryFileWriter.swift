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

  /// Writes binary data to a file using the provided closure.
  ///
  /// - Parameters:
  ///   - url: The file URL to write to. The file will be created or overwritten.
  ///   - block: A closure that receives the writer and performs write operations.
  /// - Throws: `BinaryFileWriterError` if the file cannot be created or written.
  static func write(to url: URL, _ block: (BinaryFileWriter) throws -> Void) throws {
    guard let stream = OutputStream(url: url, append: false) else {
      throw BinaryFileWriterError.cannotOpenFile(url)
    }
    let writer = BinaryFileWriter(stream: stream)
    try block(writer)
  }

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

  /// Writes a single byte.
  func writeByte(_ value: UInt8) {
    var byte = value
    stream.write(&byte, maxLength: 1)
  }

  /// Writes an array of bytes.
  func writeBytes(_ bytes: [UInt8]) {
    bytes.withUnsafeBufferPointer { buffer in
      guard let baseAddress = buffer.baseAddress else { return }
      stream.write(baseAddress, maxLength: bytes.count)
    }
  }

  /// Writes raw `Data`.
  func writeData(_ data: Data) {
    data.withUnsafeBytes { buffer in
      guard let baseAddress = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return
      }
      stream.write(baseAddress, maxLength: data.count)
    }
  }

  /// Writes an array of `Int16` values.
  func writeInt16Array(_ values: [Int16]) {
    values.withUnsafeBufferPointer { buffer in
      buffer.withMemoryRebound(to: UInt8.self) { byteBuffer in
        guard let baseAddress = byteBuffer.baseAddress else { return }
        stream.write(baseAddress, maxLength: byteBuffer.count)
      }
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

  /// Writes a 32-bit signed integer in little-endian byte order.
  func writeInt32(_ value: Int32) {
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

  /// Writes a 64-bit signed integer in little-endian byte order.
  func writeInt64(_ value: Int64) {
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
