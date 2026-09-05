public import Foundation
import MeasurementKit

/// A lightweight, `Sendable` copy of the runway facts a performance readout needs.
///
/// SwiftData models are not `Sendable`, so a ``Runway`` cannot cross into a widget timeline entry or an
/// App Intent result. ``RunwaySnapshot`` carries the name, the available distances for both legs, and
/// the true heading that wind resolves against, and nothing else.
public struct RunwaySnapshot: Sendable, RunwayOrientation {
  /// Runway designator (e.g., "28L", "09").
  public let name: String

  /// Takeoff run available, less any NOTAMed shortening.
  public let takeoffRun: Measurement<UnitLength>

  /// Takeoff distance available, less any NOTAMed shortening.
  public let takeoffDistance: Measurement<UnitLength>

  /// Landing distance available, less any NOTAMed shortening.
  public let landingDistance: Measurement<UnitLength>

  /// Runway heading in degrees true.
  public let trueHeading: Measurement<UnitAngle>

  /// Creates a snapshot from explicit values.
  ///
  /// - Parameters:
  ///   - name: Runway designator.
  ///   - takeoffRun: Takeoff run available.
  ///   - takeoffDistance: Takeoff distance available.
  ///   - landingDistance: Landing distance available.
  ///   - trueHeading: Runway heading in degrees true.
  public init(
    name: String,
    takeoffRun: Measurement<UnitLength>,
    takeoffDistance: Measurement<UnitLength>,
    landingDistance: Measurement<UnitLength>,
    trueHeading: Measurement<UnitAngle>
  ) {
    self.name = name
    self.takeoffRun = takeoffRun
    self.takeoffDistance = takeoffDistance
    self.landingDistance = landingDistance
    self.trueHeading = trueHeading
  }

  /// Copies the facts a performance readout needs out of a SwiftData runway.
  ///
  /// The distances are the NOTAMed ones the app's own screens compare against, not the published
  /// lengths: a readout that measured against pavement a NOTAM has closed would call a runway usable
  /// that the app calls short.
  ///
  /// - Parameter runway: The runway to snapshot.
  public init(from runway: Runway) {
    self.init(
      name: runway.name,
      takeoffRun: runway.notamedTakeoffRun,
      takeoffDistance: runway.notamedTakeoffDistance,
      landingDistance: runway.notamedLandingDistance,
      trueHeading: runway.trueHeading
    )
  }

  /// The distance a total-distance figure is measured against.
  ///
  /// - Parameter operation: The leg being flown.
  /// - Returns: Takeoff distance available for a takeoff, landing distance available for a landing.
  public func availableDistance(for operation: Operation) -> Measurement<UnitLength> {
    switch operation {
      case .takeoff: takeoffDistance
      case .landing: landingDistance
    }
  }

  /// The distance a ground-run figure is measured against.
  ///
  /// Takeoff run and takeoff distance differ wherever a runway has a clearway, and the ground run has
  /// to fit the run — measuring it against the longer figure would pass a takeoff that overruns the
  /// pavement.
  ///
  /// - Parameter operation: The leg being flown.
  /// - Returns: Takeoff run available for a takeoff, landing distance available for a landing.
  public func availableRun(for operation: Operation) -> Measurement<UnitLength> {
    switch operation {
      case .takeoff: takeoffRun
      case .landing: landingDistance
    }
  }
}

extension RunwaySnapshot {
  /// Name comparator that matches `Runway.NameComparator` behavior.
  public struct NameComparator: SortComparator {
    public typealias Compared = RunwaySnapshot

    /// Sort order (forward = ascending, reverse = descending).
    public var order: SortOrder = .forward

    /// Creates a comparator.
    ///
    /// - Parameter order: Sort order.
    public init(order: SortOrder = .forward) {
      self.order = order
    }

    public func compare(_ lhs: RunwaySnapshot, _ rhs: RunwaySnapshot) -> ComparisonResult {
      let result = lhs.name.localizedStandardCompare(rhs.name)
      return order == .forward ? result : result.inverted
    }
  }
}

extension ComparisonResult {
  fileprivate var inverted: ComparisonResult {
    switch self {
      case .orderedAscending: .orderedDescending
      case .orderedDescending: .orderedAscending
      case .orderedSame: .orderedSame
    }
  }
}
