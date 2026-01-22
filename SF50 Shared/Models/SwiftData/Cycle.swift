import Foundation
import SwiftData

/// Identifies the data source for cycle information.
///
/// Each data source represents a different FAA dataset that follows
/// its own publication cycle.
public enum CycleDataSource: String, Codable, CaseIterable {
  /// National Airspace System Resources - airport, runway, and facility data
  case nasr
  /// Coded Instrument Flight Procedures - approach and departure procedures
  case cifp
  /// Digital Obstacle File - obstacle data for departure analysis
  case dof
}

/// Represents a publication cycle for FAA data.
///
/// ``Cycle`` tracks the effective dates and metadata for each FAA data source.
/// Each data source (NASR, CIFP, DOF) has its own publication cycle with
/// different effective and expiration dates.
///
/// ## Topics
///
/// ### Identification
/// - ``dataSource``
/// - ``name``
///
/// ### Dates
/// - ``effective``
/// - ``expires``
///
/// ### State
/// - ``isEffective``
/// - ``isExpired``
/// - ``isNotYetActive``
@Model
public final class Cycle {
  /// Identifies the data source (NASR, CIFP, DOF).
  ///
  /// Stored as a string for SwiftData compatibility but exposed as
  /// ``CycleDataSource`` via the ``dataSource`` computed property.
  /// Public access is required to allow predicates in other modules.
  @Attribute(.unique)
  public var _dataSource: String

  /// Human-readable cycle identifier (e.g., "2501", "AIRAC 2513").
  public var name: String

  /// Date when this cycle became effective.
  public var effective: Date

  /// Date when this cycle expires.
  public var expires: Date

  /// The data source this cycle represents.
  public var dataSource: CycleDataSource {
    get { CycleDataSource(rawValue: _dataSource)! }
    set { _dataSource = newValue.rawValue }
  }

  /// Whether the current date falls within the cycle's effective period.
  public var isEffective: Bool {
    (effective..<expires).contains(Date())
  }

  /// Whether the cycle has expired.
  public var isExpired: Bool {
    Date() >= expires
  }

  /// Whether the cycle is not yet active (future effective date).
  public var isNotYetActive: Bool {
    Date() < effective
  }

  /// Creates a new cycle record.
  ///
  /// - Parameters:
  ///   - dataSource: The FAA data source this cycle represents.
  ///   - name: Human-readable cycle identifier.
  ///   - effective: Date when this cycle becomes effective.
  ///   - expires: Date when this cycle expires.
  public init(
    dataSource: CycleDataSource,
    name: String,
    effective: Date,
    expires: Date
  ) {
    self._dataSource = dataSource.rawValue
    self.name = name
    self.effective = effective
    self.expires = expires
  }
}
