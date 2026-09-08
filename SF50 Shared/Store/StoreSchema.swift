public import SwiftData

import CryptoKit
import Foundation

/// The models making up the published navigation dataset.
///
/// Nav data is replaced wholesale every 28-day cycle, so it is kept apart from anything the pilot
/// authored: the dataset arrives as a prebuilt store file and is installed by replacing that file,
/// and user data must not live inside the file being replaced.
///
/// SwiftData forbids a relationship spanning two store configurations, and enforces it by quietly
/// pulling the related model back into the configuration rather than by raising an error — so the
/// two model sets have to stay disjoint on their own. `Store Schema` asserts that they do.
public enum NavDataSchema {
  /// Every model describing downloaded navigation data.
  public static let models: [any PersistentModel.Type] = [
    Airport.self,
    Runway.self,
    Obstacle.self,
    Navaid.self,
    Procedure.self,
    ProcedureSegment.self,
    Leg.self,
    Cycle.self
  ]

  /// The schema these models form.
  public static let schema = Schema(models)

  /// A digest of the nav-data schema's shape, identifying the store layout this binary can read.
  ///
  /// A prebuilt store is written by a different binary than the one that reads it, so the two have
  /// to agree on the schema before the file is opened. Opening first and hoping is not equivalent:
  /// SwiftData answers a near-miss by migrating the store rather than by refusing it, which turns a
  /// mismatch into a silent slow migration instead of a clean fall back to the import path.
  public static var fingerprint: String { schema.shapeFingerprint }
}

/// The models holding what the pilot authored, in a store no data cycle replaces.
public enum UserDataSchema {
  /// Every model describing user-authored data.
  public static let models: [any PersistentModel.Type] = [NOTAM.self, Scenario.self]

  /// The schema these models form, as the configuration opening the user store names it.
  public static let schema = Schema(models)
}

/// Both stores' models together, as a single container's schema describes them.
public enum AppSchema {
  /// Every model the app persists.
  public static let models = NavDataSchema.models + UserDataSchema.models

  /// The schema these models form.
  public static let schema = Schema(models)
}

extension Schema {
  /// A digest over this schema's entities, attributes and relationships.
  ///
  /// Rendered explicitly rather than by encoding `Schema` itself, so the digest changes only when
  /// the store's shape changes and not when an unrelated detail of SwiftData's own encoding does.
  var shapeFingerprint: String {
    let digest = SHA256.hash(data: Data(canonicalShapeDescription.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private var canonicalShapeDescription: String {
    entities.sorted { $0.name < $1.name }.map(\.canonicalShapeDescription).joined(separator: "\n")
  }
}

extension Schema.Entity {
  fileprivate var canonicalShapeDescription: String {
    ([name] + attributeDescriptions + relationshipDescriptions).joined(separator: "|")
  }

  private var attributeDescriptions: [String] {
    attributes.sorted { $0.name < $1.name }
      .map { "\($0.name):\($0.valueType):\($0.isOptional ? "optional" : "required")" }
  }

  private var relationshipDescriptions: [String] {
    relationships.sorted { $0.name < $1.name }
      .map {
        let rule = String(describing: $0.deleteRule)
        return "\($0.name)->\($0.destination):\(rule):\($0.isOptional ? "optional" : "required")"
      }
  }
}
