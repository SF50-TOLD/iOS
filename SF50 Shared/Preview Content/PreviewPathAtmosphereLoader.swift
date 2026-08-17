import Foundation

/// An atmosphere loader that answers with a fixed outcome instead of the network.
///
/// Lets a preview or a test show each state the weather layers can be in — including the one a
/// go-around profile is most often planned in, with no connection at all.
public actor PreviewPathAtmosphereLoader: PathAtmosphereLoading {

  private let outcome: Outcome

  /// Creates a loader that always answers the same way.
  ///
  /// - Parameter outcome: What to answer with.
  public init(_ outcome: Outcome) {
    self.outcome = outcome
  }

  public func atmosphere(
    along _: [PathAtmosphereLoader.PathPoint],
    at _: Date
  ) throws -> PathAtmosphere {
    switch outcome {
      case .loaded(let atmosphere): atmosphere
      case .offline: throw PathAtmosphereLoader.Failure.offline
      case .unavailable: throw PathAtmosphereLoader.Failure.unavailable
    }
  }

  /// What this loader answers with.
  public enum Outcome: Sendable {
    /// A sample atmosphere.
    case loaded(PathAtmosphere)

    /// Refuses as though the device had no connection.
    case offline

    /// Refuses as though the service couldn't answer.
    case unavailable
  }
}
