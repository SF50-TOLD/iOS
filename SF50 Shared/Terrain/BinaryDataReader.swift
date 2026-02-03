import Foundation

/// Efficiently reads binary data from a `Data` buffer with a sequential cursor.
///
/// `BinaryDataReader` provides type-safe methods for reading integers and raw bytes
/// from a binary buffer, automatically advancing a cursor position after each read.
///
/// ## Usage
///
/// ```swift
/// let reader = BinaryDataReader(data: fileData)
///
/// let magic = try reader.readBytes(4)
/// let version = try reader.readUInt16()
/// let count = try reader.readUInt32()
///
/// for _ in 0..<count {
///     let lat = try reader.readInt16()
///     let lon = try reader.readInt16()
/// }
/// ```
struct BinaryDataReader {

  /// The underlying data buffer.
  private let data: Data

  /// Current read position.
  private(set) var offset: Int = 0

  /// Number of bytes remaining to read.
  var bytesRemaining: Int { data.count - offset }

  /// Creates a reader for the given data.
  init(data: Data) {
    self.data = data
  }

  // MARK: - Cursor Control

  /// Advances the cursor by the specified number of bytes.
  mutating func skip(_ count: Int) throws {
    guard offset + count <= data.count else {
      throw BinaryDataReaderError.endOfData(needed: count, available: bytesRemaining)
    }
    offset += count
  }

  /// Resets the cursor to the beginning.
  mutating func reset() {
    offset = 0
  }

  /// Seeks to an absolute offset.
  mutating func seek(to position: Int) throws {
    guard position >= 0 && position <= data.count else {
      throw BinaryDataReaderError.invalidOffset(position, dataSize: data.count)
    }
    offset = position
  }

  // MARK: - Byte Reading

  /// Reads a single byte.
  mutating func readByte() throws -> UInt8 {
    guard offset + 1 <= data.count else {
      throw BinaryDataReaderError.endOfData(needed: 1, available: bytesRemaining)
    }
    let value = data[offset]
    offset += 1
    return value
  }

  /// Reads the specified number of bytes.
  mutating func readBytes(_ count: Int) throws -> Data {
    guard offset + count <= data.count else {
      throw BinaryDataReaderError.endOfData(needed: count, available: bytesRemaining)
    }
    let result = data[offset..<(offset + count)]
    offset += count
    return result
  }

  /// Reads bytes as an ASCII string.
  mutating func readASCII(_ count: Int) throws -> String {
    let bytes = try readBytes(count)
    guard let string = String(data: bytes, encoding: .ascii) else {
      throw BinaryDataReaderError.invalidASCII
    }
    return string
  }

  // MARK: - Integer Reading (Little Endian)

  /// Reads a 16-bit unsigned integer in little-endian byte order.
  mutating func readUInt16() throws -> UInt16 {
    try readInteger()
  }

  /// Reads a 16-bit signed integer in little-endian byte order.
  mutating func readInt16() throws -> Int16 {
    try readInteger()
  }

  /// Reads a 32-bit unsigned integer in little-endian byte order.
  mutating func readUInt32() throws -> UInt32 {
    try readInteger()
  }

  /// Reads a 32-bit signed integer in little-endian byte order.
  mutating func readInt32() throws -> Int32 {
    try readInteger()
  }

  /// Reads a 64-bit unsigned integer in little-endian byte order.
  mutating func readUInt64() throws -> UInt64 {
    try readInteger()
  }

  /// Reads a 64-bit signed integer in little-endian byte order.
  mutating func readInt64() throws -> Int64 {
    try readInteger()
  }

  // MARK: - Generic Integer Reading

  /// Reads a fixed-width integer in little-endian byte order.
  private mutating func readInteger<T: FixedWidthInteger>() throws -> T {
    let size = MemoryLayout<T>.size
    guard offset + size <= data.count else {
      throw BinaryDataReaderError.endOfData(needed: size, available: bytesRemaining)
    }

    let value = data.withUnsafeBytes { buffer in
      buffer.load(fromByteOffset: offset, as: T.self)
    }
    offset += size
    return T(littleEndian: value)
  }
}

// MARK: - Errors

enum BinaryDataReaderError: LocalizedError {
  case endOfData(needed: Int, available: Int)
  case invalidOffset(Int, dataSize: Int)
  case invalidASCII

  var errorDescription: String? {
    switch self {
      case .endOfData(let needed, let available):
        return "Unexpected end of data: needed \(needed) bytes but only \(available) available"
      case .invalidOffset(let offset, let dataSize):
        return "Invalid offset \(offset) for data of size \(dataSize)"
      case .invalidASCII:
        return "Data is not valid ASCII"
    }
  }
}
