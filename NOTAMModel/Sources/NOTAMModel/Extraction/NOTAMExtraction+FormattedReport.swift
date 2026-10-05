internal import Foundation
public import NOTAMParsing

extension NOTAMExtraction {
  /// The extraction a formatted report states, in the same shape as a model reading, so both reach
  /// the app through one mapping. A report on a runway pair states its condition for each direction.
  public init(_ report: FormattedReport) {
    self.init(
      isCanceled: false,
      effects: report.effects.flatMap(RunwayEffect.effects),
      obstacles: report.effects.compactMap(\.obstacle).map(Obstacle.init)
    )
  }
}

extension NOTAMExtraction.RunwayEffect {
  /// One effect per direction `effect` names, or none when it states no surface condition.
  fileprivate static func effects(_ effect: FormattedReport.RunwayEffect) -> [Self] {
    guard let condition = effect.surfaceCondition.map(NOTAMExtraction.SurfaceCondition.init) else {
      return []
    }
    let directions: [String?] = effect.runway.map(RunwayDesignator.directions) ?? [nil]
    return directions.map { .init(runway: $0, closure: .none, surfaceCondition: condition) }
  }
}

extension NOTAMExtraction.SurfaceCondition {
  init(_ condition: FormattedReport.SurfaceCondition) {
    self.init(
      rwyCC: condition.rwyCC,
      contaminants: condition.contaminants.map(NOTAMExtraction.Contaminant.init).reduce(into: []) {
        if !$0.contains($1) { $0.append($1) }
      }
    )
  }
}

extension NOTAMExtraction.Contaminant {
  init(_ contaminant: FormattedReport.Contaminant) {
    self.init(
      type: .init(contaminant.type),
      coveragePercent: contaminant.coveragePercent,
      depth: contaminant.depth.map {
        $0.unit == UnitLength.millimeters
          ? .init(value: $0.value, unit: .mm)
          : .init(value: $0.converted(to: .inches).value, unit: .in)
      }
    )
  }
}

extension NOTAMExtraction.ContaminantType {
  init(_ type: FormattedReport.ContaminantType) {
    switch type {
      case .wet: self = .wet
      case .water: self = .water
      case .slush: self = .slush
      case .wetSnow: self = .wetSnow
      case .drySnow: self = .drySnow
      case .compactedSnow: self = .compactedSnow
      case .frost: self = .frost
      case .ice: self = .ice
      case .wetIce: self = .wetIce
      case .slushOverIce: self = .slushOverIce
      case .waterOverCompactedSnow: self = .waterOverCompactedSnow
      case .drySnowOverCompactedSnow: self = .drySnowOverCompactedSnow
      case .wetSnowOverCompactedSnow: self = .wetSnowOverCompactedSnow
      case .drySnowOverIce: self = .drySnowOverIce
      case .wetSnowOverIce: self = .wetSnowOverIce
      case .other: self = .other
    }
  }
}

extension NOTAMExtraction.Obstacle {
  /// The FAA obstacle report's MSL height (or its AGL height when the MSL one is unknown), its
  /// distance and compass direction from the runway end it names, or from the airport.
  init(_ obstacle: FormattedReport.Obstacle) {
    self.init(
      height: obstacle.heightMSL.map { .feet($0, datum: .MSL) }
        ?? obstacle.heightAGL.map { .feet($0, datum: .AGL) },
      distance: .init(value: obstacle.distance.converted(to: .nauticalMiles).value, unit: .nm),
      reference: .init(obstacle.runwayEnd),
      direction: NOTAMExtraction.CompassPoint(rawValue: obstacle.direction.rawValue).map {
        .compass($0)
      }
    )
  }
}

extension NOTAMExtraction.ObstacleReference {
  /// The runway end an obstacle report names, or the airport when it names none.
  fileprivate init(_ end: FormattedReport.RunwayEnd?) {
    guard let end else {
      self.init(kind: .ARP, runway: nil)
      return
    }
    self.init(
      kind: end.end == .departure ? .departureEnd : .threshold,
      runway: RunwayDesignator.normalize(end.runway)
    )
  }
}

extension NOTAMExtraction.Height {
  fileprivate static func feet(
    _ height: Measurement<UnitLength>,
    datum: NOTAMExtraction.HeightDatum
  )
    -> Self
  {
    .init(value: height.converted(to: .feet).value, unit: .ft, datum: datum)
  }
}
