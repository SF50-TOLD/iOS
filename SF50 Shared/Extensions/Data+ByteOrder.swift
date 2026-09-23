public import Foundation

/// Writes integers in an explicit byte order.
///
/// The write-side counterpart of `RawSpan.load(fromByteOffset:as:_:)`, which reads an integer back
/// from `bytes` in a given byte order.
extension Data {
  /// Appends an integer's bytes in the given byte order.
  ///
  /// - Parameters:
  ///   - value: The integer to append.
  ///   - byteOrder: The order to lay its bytes out in.
  public mutating func append<T: FixedWidthInteger & BitwiseCopyable & ConvertibleToBytes>(
    _ value: T,
    _ byteOrder: ByteOrder
  ) {
    append(contentsOf: CollectionOfOne(value), byteOrder)
  }

  /// Appends each integer's bytes in the given byte order, growing the buffer once.
  ///
  /// - Parameters:
  ///   - values: The integers to append, in order.
  ///   - byteOrder: The order to lay each one's bytes out in.
  public mutating func append<Values: Collection>(contentsOf values: Values, _ byteOrder: ByteOrder)
  where Values.Element: FixedWidthInteger & BitwiseCopyable & ConvertibleToBytes {
    let width = MemoryLayout<Values.Element>.size,
      start = count
    append(contentsOf: repeatElement(0, count: values.count * width))
    var bytes = mutableBytes
    for (index, value) in values.enumerated() {
      bytes.storeBytes(
        of: value,
        toByteOffset: start + index * width,
        as: Values.Element.self,
        byteOrder
      )
    }
  }
}
