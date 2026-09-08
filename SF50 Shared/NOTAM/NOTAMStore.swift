public import SwiftData

import Foundation

/// Resolves the NOTAMs a pilot entered against the runways they restrict.
///
/// A ``NOTAM`` names its runway by airport record ID and designator rather than pointing at it, so
/// something has to do the lookup a relationship used to do. That indirection is what lets nav data
/// live in a store replaced whole every cycle while the pilot's own entries sit outside it.
///
/// Resolution is deliberately fallible. A runway is renamed whenever magnetic drift moves its
/// designator, and a renamed runway must show *no* NOTAM rather than another runway's.
public struct NOTAMStore {
  private let context: ModelContext

  /// Creates a store reading and writing through `context`.
  ///
  /// - Parameter context: The context holding the user's NOTAMs.
  public init(context: ModelContext) {
    self.context = context
  }

  /// The NOTAM restricting `runway`, if the pilot entered one.
  ///
  /// - Parameter runway: The runway to look up.
  /// - Returns: The matching NOTAM, or `nil` if none matches — including when the runway has been
  ///   renamed since the NOTAM was written.
  public func notam(for runway: Runway) -> NOTAM? {
    let recordID = runway.airport.recordID,
      name = runway.name
    var descriptor = FetchDescriptor<NOTAM>(
      predicate: #Predicate { $0.airportRecordID == recordID && $0.runwayName == name }
    )
    descriptor.fetchLimit = 1
    return try? context.fetch(descriptor).first
  }

  /// Every NOTAM at `airport`, keyed by the runway designator it restricts.
  ///
  /// A runway picker draws every runway at an airport at once, so it resolves them in one fetch
  /// rather than one per row.
  ///
  /// - Parameter airport: The airport to look up.
  /// - Returns: The airport's NOTAMs, keyed by runway name.
  public func notams(at airport: Airport) -> [String: NOTAM] {
    let recordID = airport.recordID
    let descriptor = FetchDescriptor<NOTAM>(
      predicate: #Predicate { $0.airportRecordID == recordID }
    )
    guard let notams = try? context.fetch(descriptor) else { return [:] }
    return Dictionary(notams.map { ($0.runwayName, $0) }, uniquingKeysWith: { first, _ in first })
  }

  /// The NOTAM restricting `runway`, creating an empty one if the pilot has not entered any.
  ///
  /// This is the only place a NOTAM is created, which is what keeps it to one per runway. The
  /// schema does not say so with a uniqueness constraint: adding one to an entity that already has
  /// rows is not a change SwiftData can migrate lightly, and every NOTAM predating this shape would
  /// arrive holding the same empty identifiers.
  ///
  /// - Parameter runway: The runway to annotate.
  /// - Returns: The runway's NOTAM.
  public func upsert(for runway: Runway) -> NOTAM {
    if let existing = notam(for: runway) { return existing }
    let notam = NOTAM(runway: runway)
    context.insert(notam)
    return notam
  }
}
