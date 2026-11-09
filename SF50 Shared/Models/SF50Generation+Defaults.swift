public import Defaults

/// Stores an ``SF50Generation`` in `UserDefaults` as its raw value.
public struct SF50GenerationBridge: Defaults.Bridge, Sendable {
  public typealias Value = SF50Generation
  public typealias Serializable = String

  public func serialize(_ value: SF50Generation?) -> String? {
    value?.rawValue
  }

  public func deserialize(_ object: String?) -> SF50Generation? {
    guard let object else { return nil }
    return SF50Generation(rawValue: object)
  }
}

extension SF50Generation: @retroactive Defaults.Serializable {
  public static let bridge = SF50GenerationBridge()
}
