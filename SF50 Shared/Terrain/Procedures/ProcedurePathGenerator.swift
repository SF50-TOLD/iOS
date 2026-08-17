import CoreLocation
import Foundation

/// Generates geographic flight paths from instrument procedure leg sequences.
public struct ProcedurePathGenerator {

  // MARK: - Constants

  static let groundStepNM: Double = 0.1
  static let maxSteps: Int = 1000

  /// Screen height (35 ft AFE) — the altitude above field elevation at which
  /// the aircraft is considered airborne for obstacle/terrain evaluation.
  public static let screenHeight = Measurement(value: 35, unit: UnitLength.feet)

  /// Default altitude ceiling above field elevation when no restrictions exist.
  private static let defaultCeilingAboveFieldFt: Double = 2000

  /// Altitude buffer above highest restriction for procedure ceiling.
  private static let ceilingBufferAboveRestrictionFt: Double = 1000

  // MARK: - Stored Properties

  private let climbProfile: ClimbProfile
  private let segments: ClimbSegments
  private let variation: Measurement<UnitAngle>

  // MARK: - Initializer

  public init(
    climbProfile: ClimbProfile,
    schedule: ClimbSchedule,
    magneticVariation: Measurement<UnitAngle>
  ) {
    self.climbProfile = climbProfile
    self.segments = ClimbSegments(schedule: schedule)
    self.variation = magneticVariation
  }

  // MARK: - Helpers

  /// Extracts the target altitude in feet from an altitude restriction for *ToAltitude legs.
  static func extractTargetAltitude(
    from restriction: AltitudeRestriction?
  ) -> Double? {
    guard let restriction else { return nil }
    switch restriction {
      case .at(let altitude):
        return altitude.converted(to: .feet).value
      case .atOrAbove(let altitude):
        return altitude.converted(to: .feet).value
      case .atOrBelow(let altitude):
        return altitude.converted(to: .feet).value
      case .between(let min, _):
        return min.converted(to: .feet).value
    }
  }

  /// Converts DME slant range to ground distance.
  /// Falls back to slant range if elevation unknown or geometry invalid.
  static func groundDistanceFromDME(
    slantRangeNM: Double,
    aircraftAltitudeFt: Double,
    navaidElevation: Measurement<UnitLength>?
  ) -> Double {
    guard let elevation = navaidElevation else { return slantRangeNM }
    let navaidAltitudeFt = elevation.converted(to: .feet).value
    let altDiffNM = (aircraftAltitudeFt - navaidAltitudeFt) / feetPerNauticalMile
    let slantSq = slantRangeNM * slantRangeNM
    let altSq = altDiffNM * altDiffNM
    guard slantSq > altSq else { return slantRangeNM }
    return (slantSq - altSq).squareRoot()
  }

  /// Computes per-leg level-off ceilings by scanning upcoming atOrBelow/between
  /// restrictions. Since the aircraft can only climb, an upcoming atOrBelow ceiling
  /// must be applied to all prior legs so the aircraft levels off in time.
  ///
  /// Returns an array parallel to `legs` where each element is the minimum
  /// atOrBelow ceiling from that leg through the end of the procedure.
  static func lookAheadLevelOffCeilings(for legs: [Leg]) -> [Double?] {
    var ceilings: [Double?] = Array(repeating: nil, count: legs.count)
    var minCeiling: Double?
    for index in stride(from: legs.count - 1, through: 0, by: -1) {
      if let restriction = legs[index].altitudeRestriction {
        switch restriction {
          case .atOrBelow(let maxAlt):
            let ft = maxAlt.converted(to: .feet).value
            minCeiling = min(minCeiling ?? ft, ft)
          case .between(_, let maxAlt):
            let ft = maxAlt.converted(to: .feet).value
            minCeiling = min(minCeiling ?? ft, ft)
          default:
            break
        }
      }
      ceilings[index] = minCeiling
    }
    return ceilings
  }

  /// Computes an altitude ceiling from a procedure's altitude restrictions.
  /// Returns 1000 ft above the highest referenced restriction altitude,
  /// or `startAltitudeFt + 2000` if no restrictions are present.
  private static func altitudeCeiling(
    from legs: [Leg],
    startAltitudeFt: Double
  ) -> Double {
    var highestRestrictionFt: Double?
    for leg in legs {
      if let altitude = highestAltitude(in: leg.altitudeRestriction) {
        highestRestrictionFt = max(highestRestrictionFt ?? altitude, altitude)
      }
    }
    guard let highestRestrictionFt else { return startAltitudeFt + defaultCeilingAboveFieldFt }
    return highestRestrictionFt + ceilingBufferAboveRestrictionFt
  }

  /// Returns the highest altitude value referenced by a restriction.
  private static func highestAltitude(
    in restriction: AltitudeRestriction?
  ) -> Double? {
    guard let restriction else { return nil }
    switch restriction {
      case .at(let altitude), .atOrAbove(let altitude), .atOrBelow(let altitude):
        return altitude.converted(to: .feet).value
      case .between(_, let max):
        return max.converted(to: .feet).value
    }
  }

  // MARK: - Public API

  /// Generates a path for a departure procedure.
  /// Returns nil if any leg cannot be resolved to a geographic path.
  public func departurePath(
    from legs: [Leg],
    takeoffPoint: CLLocationCoordinate2D,
    takeoffPointAltitudeFt: Double
  ) -> ProcedurePath? {
    guard !legs.isEmpty else { return nil }

    let ceiling = Self.altitudeCeiling(from: legs, startAltitudeFt: takeoffPointAltitudeFt)
    let levelOffCeilings = Self.lookAheadLevelOffCeilings(for: legs)

    var points: [ProcedurePath.Point] = []
    var cumulativeNM = 0.0,
      currentAltitudeFt = takeoffPointAltitudeFt,
      elapsedTimeSeconds = 0.0,
      previousCoord = takeoffPoint

    // Prepend takeoff point as origin
    points.append(
      .init(
        coordinate: takeoffPoint,
        distanceNM: 0,
        altitudeFt: takeoffPointAltitudeFt,
        elapsedTimeSeconds: 0,
        altitudeRestriction: nil
      )
    )

    for (index, leg) in legs.enumerated() {
      let isLast = index == legs.count - 1

      guard
        let segmentResult = processLeg(
          leg: leg,
          nextLeg: index + 1 < legs.count ? legs[index + 1] : nil,
          previousCoord: previousCoord,
          cumulativeNM: cumulativeNM,
          currentAltitudeFt: currentAltitudeFt,
          elapsedTimeSeconds: elapsedTimeSeconds,
          isLast: isLast,
          altitudeCeiling: ceiling,
          lookAheadLevelOffFt: levelOffCeilings[index]
        )
      else {
        return nil
      }

      points.append(contentsOf: segmentResult.points)
      cumulativeNM = segmentResult.cumulativeNM
      currentAltitudeFt = segmentResult.altitudeFt
      elapsedTimeSeconds = segmentResult.elapsedTimeSeconds
      previousCoord = segmentResult.lastCoord

      if currentAltitudeFt >= ceiling { break }
    }

    return ProcedurePath(points: points)
  }

  /// Generates a path for a missed approach procedure.
  /// Returns nil if any leg cannot be resolved to a geographic path.
  public func missedApproachPath(
    from legs: [Leg],
    startCoordinate: CLLocationCoordinate2D,
    startAltitudeFt: Double
  ) -> ProcedurePath? {
    guard !legs.isEmpty else { return nil }

    let ceiling = Self.altitudeCeiling(from: legs, startAltitudeFt: startAltitudeFt)
    let levelOffCeilings = Self.lookAheadLevelOffCeilings(for: legs)

    var points: [ProcedurePath.Point] = []
    var cumulativeNM = 0.0
    var currentAltitudeFt = startAltitudeFt
    var elapsedTimeSeconds = 0.0
    var previousCoord = startCoordinate

    // Prepend start coordinate as origin
    points.append(
      .init(
        coordinate: startCoordinate,
        distanceNM: 0,
        altitudeFt: startAltitudeFt,
        elapsedTimeSeconds: 0,
        altitudeRestriction: nil
      )
    )

    for (index, leg) in legs.enumerated() {
      let isLast = index == legs.count - 1

      guard
        let segmentResult = processLeg(
          leg: leg,
          nextLeg: index + 1 < legs.count ? legs[index + 1] : nil,
          previousCoord: previousCoord,
          cumulativeNM: cumulativeNM,
          currentAltitudeFt: currentAltitudeFt,
          elapsedTimeSeconds: elapsedTimeSeconds,
          isLast: isLast,
          altitudeCeiling: ceiling,
          lookAheadLevelOffFt: levelOffCeilings[index]
        )
      else {
        return nil
      }

      points.append(contentsOf: segmentResult.points)
      cumulativeNM = segmentResult.cumulativeNM
      currentAltitudeFt = segmentResult.altitudeFt
      elapsedTimeSeconds = segmentResult.elapsedTimeSeconds
      previousCoord = segmentResult.lastCoord

      if currentAltitudeFt >= ceiling { break }
    }

    return ProcedurePath(points: points)
  }

  /// Generates a straight-line climb path along a fixed heading or track.
  public func headingPath(
    from startCoordinate: CLLocationCoordinate2D,
    magneticDirection: Measurement<UnitAngle>,
    isHeading: Bool,
    startAltitudeFt: Double,
    targetAltitudeFt: Double,
    altitudeCeiling: Double = .infinity
  ) -> ProcedurePath? {
    let trueDir = magneticDirection.toTrue(variation: variation)
      .converted(to: .degrees).value
    let direction: DirectionMode =
      isHeading
      ? .heading(trueHeading: trueDir)
      : .course(trueBearing: trueDir)

    var points: [ProcedurePath.Point] = [
      .init(
        coordinate: startCoordinate,
        distanceNM: 0,
        altitudeFt: startAltitudeFt,
        elapsedTimeSeconds: 0,
        altitudeRestriction: nil
      )
    ]

    var stepper = LinearStepper(
      config: StepperConfig(
        climbProfile: climbProfile,
        segments: segments,
        altitudeCeilingFt: altitudeCeiling,
        finalAltitudeRestriction: nil,
        fixName: nil,
        levelOffAltitudeFt: nil
      ),
      state: .init(
        coordinate: startCoordinate,
        cumulativeGroundNM: 0,
        altitudeFt: startAltitudeFt,
        elapsedTimeSeconds: 0
      ),
      direction: direction,
      termination: .altitude(targetFt: targetAltitudeFt)
    )
    guard let result = stepper.run() else { return nil }

    points.append(contentsOf: result.points)
    return ProcedurePath(points: points)
  }

  // MARK: - Leg Processing

  private func processLeg(
    leg: Leg,
    nextLeg: Leg? = nil,
    previousCoord: CLLocationCoordinate2D,
    cumulativeNM: Double,
    currentAltitudeFt: Double,
    elapsedTimeSeconds: Double,
    isLast: Bool,
    altitudeCeiling: Double = .infinity,
    lookAheadLevelOffFt: Double? = nil
  ) -> SegmentResult? {
    guard let strat = strategy(for: leg.legType, nextLeg: nextLeg) else { return nil }
    guard
      let resolved = strat.resolve(
        leg: leg,
        previousCoord: previousCoord,
        currentAltitudeFt: currentAltitudeFt,
        isLast: isLast,
        variation: variation
      )
    else { return nil }

    let fixName: String?
    if let identifier = leg.identifier {
      fixName = identifier
    } else if case .linear(_, _, .altitude(let targetFt)) = resolved {
      fixName = "(\(Int(targetFt).formatted()))"
    } else if case .linear(_, _, .dme(_, let targetNM)) = resolved {
      fixName = "(D\(targetNM.formatted(.number.precision(.fractionLength(0...1)))))"
    } else if case .linear(_, _, .groundDistance(_, let targetNM)) = resolved {
      fixName = "(\(targetNM.formatted(.number.precision(.fractionLength(0...1)))) NM)"
    } else {
      fixName = nil
    }

    let levelOffAltitudeFt = lookAheadLevelOffFt

    let stepperConfig = StepperConfig(
      climbProfile: climbProfile,
      segments: segments,
      altitudeCeilingFt: altitudeCeiling,
      finalAltitudeRestriction: leg.altitudeRestriction,
      fixName: fixName,
      levelOffAltitudeFt: levelOffAltitudeFt
    )

    let result: SegmentResult?
    switch resolved {
      case .linear(let from, let direction, let termination):
        var stepper = LinearStepper(
          config: stepperConfig,
          state: .init(
            coordinate: from,
            cumulativeGroundNM: cumulativeNM,
            altitudeFt: currentAltitudeFt,
            elapsedTimeSeconds: elapsedTimeSeconds
          ),
          direction: direction,
          termination: termination
        )
        result = stepper.run()
      case .arc(
        let from,
        let center,
        let radiusNM,
        let startAngleDeg,
        let endAngleDeg,
        let targetCoord
      ):
        var stepper = ArcStepper(
          config: stepperConfig,
          state: .init(
            coordinate: from,
            cumulativeGroundNM: cumulativeNM,
            altitudeFt: currentAltitudeFt,
            elapsedTimeSeconds: elapsedTimeSeconds
          ),
          center: center,
          radiusNM: radiusNM,
          startAngleDeg: startAngleDeg,
          endAngleDeg: endAngleDeg,
          targetCoord: targetCoord
        )
        result = stepper.run()
    }

    guard let result else { return nil }

    return result
  }

  /// Returns the appropriate strategy for a leg type, or `nil` for non-plottable types.
  private func strategy(for legType: LegType, nextLeg: Leg? = nil) -> (any LegStrategy)? {
    switch legType {
      case .initialFix, .trackToFix, .courseToFix, .directToFix:
        return FixTerminatedStrategy()
      case .holdToFix, .holdToAltitude, .holdManual, .procedureTurn:
        return TerminalOnlyStrategy()
      case .fixToAltitude(let course):
        return ToAltitudeStrategy(magnetic: course, isHeading: false)
      case .courseToAltitude(let course):
        return ToAltitudeStrategy(magnetic: course, isHeading: false)
      case .headingToAltitude(let heading):
        return ToAltitudeStrategy(magnetic: heading, isHeading: true)
      case .courseToDME(let course):
        return ToDMEStrategy(magnetic: course, isHeading: false)
      case .headingToDME(let heading):
        return ToDMEStrategy(magnetic: heading, isHeading: true)
      case .trackFromFixDME(let course):
        return TrackFromFixStrategy(magnetic: course, useDME: true)
      case .trackFromFixDistance(let course):
        return TrackFromFixStrategy(magnetic: course, useDME: false)
      case .radiusToFix(let arcRadius, let course):
        return ArcStrategy(arcRadius: arcRadius, magnetic: course, isRadiusToFix: true)
      case .arcToFix(let arcRadius, let course):
        return ArcStrategy(arcRadius: arcRadius, magnetic: course, isRadiusToFix: false)
      case .courseToIntercept(let course):
        guard let nextLeg,
          let interceptCourse = nextLeg.legType.magneticCourse,
          let pointOnCourse = nextLeg.coordinate
        else { return nil }
        return ToInterceptStrategy(
          magnetic: course,
          isHeading: false,
          interceptCourseMagnetic: interceptCourse,
          pointOnCourse: pointOnCourse
        )
      case .headingToIntercept(let heading):
        guard let nextLeg,
          let interceptCourse = nextLeg.legType.magneticCourse,
          let pointOnCourse = nextLeg.coordinate
        else { return nil }
        return ToInterceptStrategy(
          magnetic: heading,
          isHeading: true,
          interceptCourseMagnetic: interceptCourse,
          pointOnCourse: pointOnCourse
        )
      case .courseToRadial(let course):
        return ToRadialStrategy(magnetic: course, isHeading: false)
      case .headingToRadial(let heading):
        return ToRadialStrategy(magnetic: heading, isHeading: true)
    }
  }

  // MARK: - Public Types

  /// Upper bound that ends a climb segment.
  public enum SegmentBound: Sendable {
    case time(Measurement<UnitDuration>)
    case altitude(Measurement<UnitLength>)
  }

  /// A single segment in a climb schedule.
  public struct ClimbSegment: Sendable {
    public let profile: ClimbProfile.ProfileType
    public let upperBound: SegmentBound?  // nil = final segment (runs to end)

    public init(profile: ClimbProfile.ProfileType, upperBound: SegmentBound? = nil) {
      self.profile = profile
      self.upperBound = upperBound
    }
  }

  /// Climb schedule configuration for path generation.
  public struct ClimbSchedule: Sendable {
    public let segments: [ClimbSegment]

    public init(segments: [ClimbSegment]) {
      self.segments = segments
    }
  }

  // MARK: - Internal Types

  /// How the aircraft tracks over the ground at each step.
  enum DirectionMode {
    /// Fly a fixed course (pilot crabs); ground track = true course.
    case course(trueBearing: Double)
    /// Fly a fixed heading; ground track from wind triangle.
    case heading(trueHeading: Double)
    /// Fly toward a fix (bearing recalculated each step, course-based).
    case directTo(target: CLLocationCoordinate2D)
  }

  /// When the step loop terminates.
  enum TerminationCondition {
    case fix(target: CLLocationCoordinate2D)
    case altitude(targetFt: Double)
    case dme(reference: CLLocationCoordinate2D, targetGroundNM: Double)
    case groundDistance(origin: CLLocationCoordinate2D, targetNM: Double)
    case courseIntercept(courseTrueDeg: Double, pointOnCourse: CLLocationCoordinate2D)
  }

  /// What the step engines consume.
  enum ResolvedSegment {
    case linear(
      from: CLLocationCoordinate2D,
      direction: DirectionMode,
      termination: TerminationCondition
    )
    case arc(
      from: CLLocationCoordinate2D,
      center: CLLocationCoordinate2D,
      radiusNM: Double,
      startAngleDeg: Double,
      endAngleDeg: Double,
      targetCoord: CLLocationCoordinate2D
    )
  }

  /// Mutable state carried through stepping.
  struct StepState {
    var coordinate: CLLocationCoordinate2D
    var cumulativeGroundNM: Double
    var altitudeFt: Double
    var elapsedTimeSeconds: Double
  }

  struct SegmentResult {
    let points: [ProcedurePath.Point]
    let cumulativeNM: Double
    let altitudeFt: Double
    let elapsedTimeSeconds: Double
    let lastCoord: CLLocationCoordinate2D
  }

  /// Pre-processed climb segments with resolved bounds for efficient per-step lookup.
  struct ClimbSegments {
    let segments: [(profile: ClimbProfile.ProfileType, altFt: Double?, timeSec: Double?)]

    init(schedule: ClimbSchedule) {
      self.segments = schedule.segments.map { segment in
        switch segment.upperBound {
          case .time(let t):
            return (segment.profile, nil, t.converted(to: .seconds).value)
          case .altitude(let a):
            return (segment.profile, a.converted(to: .feet).value, nil)
          case nil:
            return (segment.profile, nil, nil)
        }
      }
    }

    /// Returns the active profile for the current elapsed time and altitude.
    /// Each segment is active until its bound is exceeded, then the next takes over.
    func activeProfile(elapsedSeconds: Double, altitudeFt: Double) -> ClimbProfile.ProfileType {
      for segment in segments {
        if let altFt = segment.altFt, altitudeFt >= altFt { continue }
        if let timeSec = segment.timeSec, elapsedSeconds >= timeSec { continue }
        return segment.profile
      }
      return segments.last!.profile
    }

    /// Returns profiles from segments after the currently active one, for fallback lookup.
    func fallbackProfiles(
      elapsedSeconds: Double,
      altitudeFt: Double
    ) -> [ClimbProfile.ProfileType] {
      var foundActive = false
      var result: [ClimbProfile.ProfileType] = []
      for segment in segments {
        if !foundActive {
          let pastAlt = segment.altFt.map { altitudeFt >= $0 } ?? false
          let pastTime = segment.timeSec.map { elapsedSeconds >= $0 } ?? false
          if !pastAlt && !pastTime {
            foundActive = true
            continue  // skip the active segment itself
          }
        } else {
          result.append(segment.profile)
        }
      }
      return result
    }
  }
}
