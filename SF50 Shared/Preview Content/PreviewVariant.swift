/// One named input to a `#Preview(_:arguments:)` group.
///
/// The canvas labels each variant in a group by its description, so wrapping a value with a name
/// keeps the variants as distinguishable as separate named previews would be.
public struct PreviewVariant<Value>: CustomStringConvertible {
  /// The label the canvas shows for this variant.
  public let description: String

  /// The input this variant previews.
  public let value: Value

  /// Creates a named preview input.
  ///
  /// - Parameters:
  ///   - name: The label the canvas shows for this variant.
  ///   - value: The input this variant previews.
  public init(_ name: String, _ value: Value) {
    description = name
    self.value = value
  }
}
