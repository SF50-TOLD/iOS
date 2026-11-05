public import SwiftUI

/// The type of performance operation being calculated.
///
/// The app keeps its own copy of the performance models' operation: App Intents reads the cases
/// of an `AppEnum` only from the module that declares the enum, and the widget and Shortcuts
/// parameters that persist a leg are of this type.
public enum Operation: String, CaseIterable, Codable, Sendable {
  /// Takeoff performance calculation
  case takeoff
  /// Landing performance calculation
  case landing

  /// The same leg, as the performance models take it.
  public var performanceOperation: SF50Performance.Operation {
    switch self {
      case .takeoff: .takeoff
      case .landing: .landing
    }
  }

  /// The leg the performance models' operation names.
  public init(_ operation: SF50Performance.Operation) {
    switch operation {
      case .takeoff: self = .takeoff
      case .landing: self = .landing
    }
  }
}

private struct OperationKey: EnvironmentKey {
  static let defaultValue = Operation.takeoff
}

extension EnvironmentValues {
  /// The current performance operation type (takeoff or landing) for the view hierarchy.
  public var operation: Operation {
    get { self[OperationKey.self] }
    set { self[OperationKey.self] = newValue }
  }
}
