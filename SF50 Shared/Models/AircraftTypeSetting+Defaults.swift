public import Defaults

/// Stores an ``AircraftTypeSetting`` in `UserDefaults` as its raw value.
public struct AircraftTypeSettingBridge: Defaults.Bridge, Sendable {
  public typealias Value = AircraftTypeSetting
  public typealias Serializable = String

  public func serialize(_ value: AircraftTypeSetting?) -> String? {
    value?.rawValue
  }

  public func deserialize(_ object: String?) -> AircraftTypeSetting? {
    guard let object else { return nil }
    return AircraftTypeSetting(rawValue: object)
  }
}

extension AircraftTypeSetting: @retroactive Defaults.Serializable {
  public static let bridge = AircraftTypeSettingBridge()
}
