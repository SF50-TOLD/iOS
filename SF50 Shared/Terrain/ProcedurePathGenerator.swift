import CoreLocation
import Foundation

/// Generates geographic flight paths from instrument procedure leg sequences.
public struct ProcedurePathGenerator {

  // MARK: - Constants

  private static let groundStepNM: Double = 0.1
  private static let maxSteps: Int = 1000

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
  fileprivate static func extractTargetAltitude(
    from restriction: AltitudeRestriction?
  ) -> Double? {
    guard let restriction else { return nil }
    switch restriction {
      case .at(let alt):
        return alt.converted(to: .feet).value
      case .atOrAbove(let alt):
        return alt.converted(to: .feet).value
      case .atOrBelow:
        // atOrBelow is not used as a climb target
        return nil
      case .between(let min, _):
        return min.converted(to: .feet).value
    }
  }

  /// Converts DME slant range to ground distance.
  /// Falls back to slant range if elevation unknown or geometry invalid.
  fileprivate static func groundDistanceFromDME(
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

  // MARK: - Public API

  /// Generates a path for a departure procedure.
  /// Returns nil if any leg cannot be resolved to a geographic path.
  public func departurePath(
    from legs: [Leg],
    takeoffPoint: CLLocationCoordinate2D,
    takeoffPointAltitudeFt: Double
  ) -> ProcedurePath? {
    let sorted = legs.sorted { $0.sequenceIndex < $1.sequenceIndex }
    guard !sorted.isEmpty else { return nil }

    var points: [ProcedurePath.Point] = []
    var cumulativeNM = 0.0
    var currentAltitudeFt = takeoffPointAltitudeFt
    var elapsedTimeSeconds = 0.0
    var previousCoord = takeoffPoint

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

    for (index, leg) in sorted.enumerated() {
      let isLast = index == sorted.count - 1

      guard
        let segmentResult = processLeg(
          leg: leg,
          previousCoord: previousCoord,
          cumulativeNM: cumulativeNM,
          currentAltitudeFt: currentAltitudeFt,
          elapsedTimeSeconds: elapsedTimeSeconds,
          isLast: isLast
        )
      else {
        return nil
      }

      points.append(contentsOf: segmentResult.points)
      cumulativeNM = segmentResult.cumulativeNM
      currentAltitudeFt = segmentResult.altitudeFt
      elapsedTimeSeconds = segmentResult.elapsedTimeSeconds
      previousCoord = segmentResult.lastCoord
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
    let sorted = legs.sorted { $0.sequenceIndex < $1.sequenceIndex }
    guard !sorted.isEmpty else { return nil }

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

    for (index, leg) in sorted.enumerated() {
      let isLast = index == sorted.count - 1

      guard
        let segmentResult = processLeg(
          leg: leg,
          previousCoord: previousCoord,
          cumulativeNM: cumulativeNM,
          currentAltitudeFt: currentAltitudeFt,
          elapsedTimeSeconds: elapsedTimeSeconds,
          isLast: isLast
        )
      else {
        return nil
      }

      points.append(contentsOf: segmentResult.points)
      cumulativeNM = segmentResult.cumulativeNM
      currentAltitudeFt = segmentResult.altitudeFt
      elapsedTimeSeconds = segmentResult.elapsedTimeSeconds
      previousCoord = segmentResult.lastCoord
    }

    return ProcedurePath(points: points)
  }

  // MARK: - Core Step Engine

  /// Unified stepping function for all non-arc legs.
  private func stepAlongPath(
    from startCoord: CLLocationCoordinate2D,
    direction: DirectionMode,
    termination: TerminationCondition,
    cumulativeNM: Double,
    currentAltitudeFt: Double,
    elapsedTimeSeconds: Double,
    finalAltitudeRestriction: AltitudeRestriction?,
    fixName: String?
  ) -> SegmentResult? {
    var state = StepState(
      coordinate: startCoord,
      cumulativeGroundNM: cumulativeNM,
      altitudeFt: currentAltitudeFt,
      elapsedTimeSeconds: elapsedTimeSeconds
    )
    var points: [ProcedurePath.Point] = []

    for _ in 0..<Self.maxSteps {
      // 1. Look up atmospheric/performance data at current altitude
      let profile = segments.activeProfile(
        elapsedSeconds: state.elapsedTimeSeconds,
        altitudeFt: state.altitudeFt
      )
      guard let gradient = climbProfile.gradient(at: state.altitudeFt, profile: profile),
        let tas = climbProfile.trueAirspeed(at: state.altitudeFt, profile: profile)
      else { return nil }

      let windDir = climbProfile.windDirection(at: state.altitudeFt) ?? 0
      let windSpeed = climbProfile.windSpeed(at: state.altitudeFt) ?? 0

      // 2. Determine ground bearing and GS/TAS ratio
      let groundBearing: Double
      let GSOverTAS: Double

      switch direction {
        case .course(let trueBearing):
          groundBearing = trueBearing
          if windSpeed > 0 {
            let wind = GeoCalculations.windTriangle(
              trueHeading: .init(value: trueBearing, unit: .degrees),
              TASKts: tas,
              windFromTrue: .init(value: windDir, unit: .degrees),
              windSpeedKts: windSpeed
            )
            GSOverTAS = wind.groundSpeedKts / tas
          } else {
            GSOverTAS = 1.0
          }

        case .heading(let trueHeading):
          if windSpeed > 0 {
            let wind = GeoCalculations.windTriangle(
              trueHeading: .init(value: trueHeading, unit: .degrees),
              TASKts: tas,
              windFromTrue: .init(value: windDir, unit: .degrees),
              windSpeedKts: windSpeed
            )
            groundBearing = wind.groundTrack.converted(to: .degrees).value
            GSOverTAS = wind.groundSpeedKts / tas
          } else {
            groundBearing = trueHeading
            GSOverTAS = 1.0
          }

        case .directTo(let target):
          let bearing = GeoCalculations.bearing(from: state.coordinate, to: target)
            .converted(to: .degrees).value
          groundBearing = bearing
          if windSpeed > 0 {
            let wind = GeoCalculations.windTriangle(
              trueHeading: .init(value: bearing, unit: .degrees),
              TASKts: tas,
              windFromTrue: .init(value: windDir, unit: .degrees),
              windSpeedKts: windSpeed
            )
            GSOverTAS = wind.groundSpeedKts / tas
          } else {
            GSOverTAS = 1.0
          }
      }

      // 3. Guard against headwind exceeding TAS
      guard GSOverTAS > 0 else { return nil }

      // 4. Convert ground step to air step and compute step time
      let airStepNM = Self.groundStepNM / GSOverTAS
      let groundSpeedKts = tas * GSOverTAS
      let stepTimeSeconds = (Self.groundStepNM / groundSpeedKts) * 3600

      // 5. Trapezoidal altitude integration
      let g1 = gradient
      let predictedAlt = state.altitudeFt + g1 * airStepNM
      let g2 = climbProfile.gradient(at: predictedAlt, profile: profile) ?? g1
      let altGain = (g1 + g2) / 2.0 * airStepNM

      // 6. Project next position
      let nextCoord = GeoCalculations.destination(
        from: state.coordinate,
        distance: .init(value: Self.groundStepNM, unit: .nauticalMiles),
        bearing: .init(value: groundBearing, unit: .degrees)
      )

      let nextAlt = state.altitudeFt + altGain
      let nextCumulativeNM = state.cumulativeGroundNM + Self.groundStepNM
      let nextElapsedTime = state.elapsedTimeSeconds + stepTimeSeconds

      // 7. Check termination before updating state
      switch termination {
        case .fix(let target):
          let distToTarget = GeoCalculations.distanceNM(from: state.coordinate, to: target)
          if distToTarget <= Self.groundStepNM {
            let fraction = Self.groundStepNM > 0 ? distToTarget / Self.groundStepNM : 1.0
            let partialAirNM = fraction * airStepNM
            let partialG2 =
              climbProfile.gradient(at: state.altitudeFt + g1 * partialAirNM, profile: profile)
              ?? g1
            let partialAltGain = (g1 + partialG2) / 2.0 * partialAirNM
            let finalAlt = state.altitudeFt + partialAltGain
            let finalCumNM = state.cumulativeGroundNM + distToTarget
            let finalTime = state.elapsedTimeSeconds + stepTimeSeconds * fraction

            points.append(
              .init(
                coordinate: target,
                distanceNM: finalCumNM,
                altitudeFt: finalAlt,
                elapsedTimeSeconds: finalTime,
                altitudeRestriction: finalAltitudeRestriction,
                fixName: fixName
              )
            )
            return SegmentResult(
              points: points,
              cumulativeNM: finalCumNM,
              altitudeFt: finalAlt,
              elapsedTimeSeconds: finalTime,
              lastCoord: target
            )
          }

        case .altitude(let targetFt):
          if nextAlt >= targetFt {
            let altNeeded = targetFt - state.altitudeFt
            let fraction = altGain > 0 ? altNeeded / altGain : 1.0
            let partialGroundNM = Self.groundStepNM * fraction
            let finalCoord = GeoCalculations.destination(
              from: state.coordinate,
              distance: .init(value: partialGroundNM, unit: .nauticalMiles),
              bearing: .init(value: groundBearing, unit: .degrees)
            )
            let finalCumNM = state.cumulativeGroundNM + partialGroundNM
            let finalTime = state.elapsedTimeSeconds + stepTimeSeconds * fraction

            points.append(
              .init(
                coordinate: finalCoord,
                distanceNM: finalCumNM,
                altitudeFt: targetFt,
                elapsedTimeSeconds: finalTime,
                altitudeRestriction: finalAltitudeRestriction,
                fixName: fixName
              )
            )
            return SegmentResult(
              points: points,
              cumulativeNM: finalCumNM,
              altitudeFt: targetFt,
              elapsedTimeSeconds: finalTime,
              lastCoord: finalCoord
            )
          }

        case .dme(let reference, let targetGroundNM):
          let prevDist = GeoCalculations.distanceNM(from: state.coordinate, to: reference)
          let nextDist = GeoCalculations.distanceNM(from: nextCoord, to: reference)
          let movingToward = prevDist > targetGroundNM

          let crossed =
            movingToward
            ? nextDist <= targetGroundNM
            : nextDist >= targetGroundNM

          if crossed {
            let prevDelta = abs(prevDist - targetGroundNM)
            let nextDelta = abs(nextDist - targetGroundNM)
            let totalDelta = prevDelta + nextDelta
            let fraction = totalDelta > 0 ? prevDelta / totalDelta : 0.5
            let partialGroundNM = Self.groundStepNM * fraction
            let partialAirNM = partialGroundNM / GSOverTAS
            let partialG2 =
              climbProfile.gradient(at: state.altitudeFt + g1 * partialAirNM, profile: profile)
              ?? g1
            let partialAltGain = (g1 + partialG2) / 2.0 * partialAirNM

            let finalCoord = GeoCalculations.destination(
              from: state.coordinate,
              distance: .init(value: partialGroundNM, unit: .nauticalMiles),
              bearing: .init(value: groundBearing, unit: .degrees)
            )
            let finalAlt = state.altitudeFt + partialAltGain
            let finalCumNM = state.cumulativeGroundNM + partialGroundNM
            let finalTime = state.elapsedTimeSeconds + stepTimeSeconds * fraction

            points.append(
              .init(
                coordinate: finalCoord,
                distanceNM: finalCumNM,
                altitudeFt: finalAlt,
                elapsedTimeSeconds: finalTime,
                altitudeRestriction: finalAltitudeRestriction,
                fixName: fixName
              )
            )
            return SegmentResult(
              points: points,
              cumulativeNM: finalCumNM,
              altitudeFt: finalAlt,
              elapsedTimeSeconds: finalTime,
              lastCoord: finalCoord
            )
          }

        case .groundDistance(let origin, let targetNM):
          let currentDist = GeoCalculations.distanceNM(from: origin, to: nextCoord)
          if currentDist >= targetNM {
            let prevDist = GeoCalculations.distanceNM(from: origin, to: state.coordinate)
            let prevDelta = abs(prevDist - targetNM)
            let nextDelta = abs(currentDist - targetNM)
            let totalDelta = prevDelta + nextDelta
            let fraction = totalDelta > 0 ? prevDelta / totalDelta : 0.5
            let partialGroundNM = Self.groundStepNM * fraction
            let partialAirNM = partialGroundNM / GSOverTAS
            let partialG2 =
              climbProfile.gradient(at: state.altitudeFt + g1 * partialAirNM, profile: profile)
              ?? g1
            let partialAltGain = (g1 + partialG2) / 2.0 * partialAirNM

            let finalCoord = GeoCalculations.destination(
              from: state.coordinate,
              distance: .init(value: partialGroundNM, unit: .nauticalMiles),
              bearing: .init(value: groundBearing, unit: .degrees)
            )
            let finalAlt = state.altitudeFt + partialAltGain
            let finalCumNM = state.cumulativeGroundNM + partialGroundNM
            let finalTime = state.elapsedTimeSeconds + stepTimeSeconds * fraction

            points.append(
              .init(
                coordinate: finalCoord,
                distanceNM: finalCumNM,
                altitudeFt: finalAlt,
                elapsedTimeSeconds: finalTime,
                altitudeRestriction: finalAltitudeRestriction,
                fixName: fixName
              )
            )
            return SegmentResult(
              points: points,
              cumulativeNM: finalCumNM,
              altitudeFt: finalAlt,
              elapsedTimeSeconds: finalTime,
              lastCoord: finalCoord
            )
          }
      }

      // 8. Update state, emit intermediate point
      state.coordinate = nextCoord
      state.cumulativeGroundNM = nextCumulativeNM
      state.altitudeFt = nextAlt
      state.elapsedTimeSeconds = nextElapsedTime

      points.append(
        .init(
          coordinate: nextCoord,
          distanceNM: nextCumulativeNM,
          altitudeFt: nextAlt,
          elapsedTimeSeconds: nextElapsedTime
        )
      )
    }

    // Safety: max steps exceeded
    return nil
  }

  // MARK: - Arc Step Engine

  /// Stepping function for radiusToFix and arcToFix legs.
  private func stepAlongArc(
    from startCoord: CLLocationCoordinate2D,
    center: CLLocationCoordinate2D,
    radiusNM: Double,
    startAngleDeg: Double,
    endAngleDeg: Double,
    targetCoord: CLLocationCoordinate2D,
    cumulativeNM: Double,
    currentAltitudeFt: Double,
    elapsedTimeSeconds: Double,
    finalAltitudeRestriction: AltitudeRestriction?,
    fixName: String?
  ) -> SegmentResult? {
    // Compute sweep (shortest arc)
    var sweep = endAngleDeg - startAngleDeg
    if sweep > 180 { sweep -= 360 }
    if sweep < -180 { sweep += 360 }

    guard abs(sweep) > 0 else { return nil }

    // Step angle increment for ~0.1 NM arc length per step
    let stepDeg = (Self.groundStepNM / radiusNM) * (180.0 / .pi)
    let stepCount = max(1, Int(abs(sweep) / stepDeg))
    let actualStepDeg = sweep / Double(stepCount)

    var state = StepState(
      coordinate: startCoord,
      cumulativeGroundNM: cumulativeNM,
      altitudeFt: currentAltitudeFt,
      elapsedTimeSeconds: elapsedTimeSeconds
    )
    var points: [ProcedurePath.Point] = []
    var currentAngle = startAngleDeg

    for i in 1...stepCount {
      let profile = segments.activeProfile(
        elapsedSeconds: state.elapsedTimeSeconds,
        altitudeFt: state.altitudeFt
      )
      guard let gradient = climbProfile.gradient(at: state.altitudeFt, profile: profile),
        let tas = climbProfile.trueAirspeed(at: state.altitudeFt, profile: profile)
      else { return nil }

      let windDir = climbProfile.windDirection(at: state.altitudeFt) ?? 0
      let windSpeed = climbProfile.windSpeed(at: state.altitudeFt) ?? 0

      let nextAngle = startAngleDeg + actualStepDeg * Double(i)
      let normalizedAngle = nextAngle.normalizedAngle

      let nextCoord: CLLocationCoordinate2D
      let isLast = i == stepCount

      if isLast {
        // Snap final point to target coordinate
        nextCoord = targetCoord
      } else {
        nextCoord = GeoCalculations.destination(
          from: center,
          distance: .init(value: radiusNM, unit: .nauticalMiles),
          bearing: .init(value: normalizedAngle, unit: .degrees)
        )
      }

      let segGroundNM = GeoCalculations.distanceNM(from: state.coordinate, to: nextCoord)

      // Tangent bearing for wind correction
      let tangentBearing =
        sweep > 0
        ? (currentAngle + 90).normalizedAngle  // clockwise: tangent is +90
        : (currentAngle - 90).normalizedAngle  // counter-clockwise: tangent is -90

      let GSOverTAS: Double
      if windSpeed > 0 {
        let wind = GeoCalculations.windTriangle(
          trueHeading: .init(value: tangentBearing, unit: .degrees),
          TASKts: tas,
          windFromTrue: .init(value: windDir, unit: .degrees),
          windSpeedKts: windSpeed
        )
        GSOverTAS = wind.groundSpeedKts / tas
      } else {
        GSOverTAS = 1.0
      }

      guard GSOverTAS > 0 else { return nil }

      let airStepNM = segGroundNM / GSOverTAS
      let groundSpeedKts = tas * GSOverTAS
      let segTimeSeconds = groundSpeedKts > 0 ? (segGroundNM / groundSpeedKts) * 3600 : 0

      // Trapezoidal altitude integration
      let g1 = gradient
      let predictedAlt = state.altitudeFt + g1 * airStepNM
      let g2 = climbProfile.gradient(at: predictedAlt, profile: profile) ?? g1
      let altGain = (g1 + g2) / 2.0 * airStepNM

      state.coordinate = nextCoord
      state.cumulativeGroundNM += segGroundNM
      state.altitudeFt += altGain
      state.elapsedTimeSeconds += segTimeSeconds
      currentAngle = nextAngle

      points.append(
        .init(
          coordinate: nextCoord,
          distanceNM: state.cumulativeGroundNM,
          altitudeFt: state.altitudeFt,
          elapsedTimeSeconds: state.elapsedTimeSeconds,
          altitudeRestriction: isLast ? finalAltitudeRestriction : nil,
          fixName: isLast ? fixName : nil
        )
      )
    }

    return SegmentResult(
      points: points,
      cumulativeNM: state.cumulativeGroundNM,
      altitudeFt: state.altitudeFt,
      elapsedTimeSeconds: state.elapsedTimeSeconds,
      lastCoord: state.coordinate
    )
  }

  // MARK: - Leg Processing

  private func processLeg(
    leg: Leg,
    previousCoord: CLLocationCoordinate2D,
    cumulativeNM: Double,
    currentAltitudeFt: Double,
    elapsedTimeSeconds: Double,
    isLast: Bool
  ) -> SegmentResult? {
    guard let strat = strategy(for: leg.legType) else { return nil }
    guard
      let resolved = strat.resolve(
        leg: leg,
        previousCoord: previousCoord,
        currentAltitudeFt: currentAltitudeFt,
        isLast: isLast,
        variation: variation
      )
    else { return nil }

    let result: SegmentResult?
    switch resolved {
      case .linear(let from, let direction, let termination):
        result = stepAlongPath(
          from: from,
          direction: direction,
          termination: termination,
          cumulativeNM: cumulativeNM,
          currentAltitudeFt: currentAltitudeFt,
          elapsedTimeSeconds: elapsedTimeSeconds,
          finalAltitudeRestriction: leg.altitudeRestriction,
          fixName: leg.identifier
        )
      case .arc(
        let from,
        let center,
        let radiusNM,
        let startAngleDeg,
        let endAngleDeg,
        let targetCoord
      ):
        result = stepAlongArc(
          from: from,
          center: center,
          radiusNM: radiusNM,
          startAngleDeg: startAngleDeg,
          endAngleDeg: endAngleDeg,
          targetCoord: targetCoord,
          cumulativeNM: cumulativeNM,
          currentAltitudeFt: currentAltitudeFt,
          elapsedTimeSeconds: elapsedTimeSeconds,
          finalAltitudeRestriction: leg.altitudeRestriction,
          fixName: leg.identifier
        )
    }

    guard var result else { return nil }

    // Apply atOrBelow altitude capping after the segment
    if let restriction = leg.altitudeRestriction {
      if case .atOrBelow(let maxAlt) = restriction {
        let capFt = maxAlt.converted(to: .feet).value
        if result.altitudeFt > capFt {
          result = SegmentResult(
            points: result.points,
            cumulativeNM: result.cumulativeNM,
            altitudeFt: capFt,
            elapsedTimeSeconds: result.elapsedTimeSeconds,
            lastCoord: result.lastCoord
          )
        }
      }
    }

    return result
  }

  /// Returns the appropriate strategy for a leg type, or `nil` for non-plottable types.
  private func strategy(for legType: LegType) -> (any LegStrategy)? {
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
      case .courseToIntercept, .courseToRadial,
        .headingToIntercept, .headingToRadial:
        return nil
    }
  }

  // MARK: - Public Types

  /// Trigger for transitioning from first to second climb segment.
  public enum SegmentTransition: Sendable {
    case time(Measurement<UnitDuration>)
    case altitude(Measurement<UnitLength>)
  }

  /// Climb schedule configuration for path generation.
  public struct ClimbSchedule: Sendable {
    public let firstSegment: ClimbProfile.ProfileType
    public let secondSegment: ClimbProfile.ProfileType?
    public let transition: SegmentTransition?

    public init(
      firstSegment: ClimbProfile.ProfileType,
      secondSegment: ClimbProfile.ProfileType? = nil,
      transition: SegmentTransition? = nil
    ) {
      self.firstSegment = firstSegment
      self.secondSegment = secondSegment
      self.transition = transition
    }
  }

  // MARK: - Internal Types

  /// How the aircraft tracks over the ground at each step.
  private enum DirectionMode {
    /// Fly a fixed course (pilot crabs); ground track = true course.
    case course(trueBearing: Double)
    /// Fly a fixed heading; ground track from wind triangle.
    case heading(trueHeading: Double)
    /// Fly toward a fix (bearing recalculated each step, course-based).
    case directTo(target: CLLocationCoordinate2D)
  }

  /// When the step loop terminates.
  private enum TerminationCondition {
    case fix(target: CLLocationCoordinate2D)
    case altitude(targetFt: Double)
    case dme(reference: CLLocationCoordinate2D, targetGroundNM: Double)
    case groundDistance(origin: CLLocationCoordinate2D, targetNM: Double)
  }

  /// What the step engines consume.
  private enum ResolvedSegment {
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
  private struct StepState {
    var coordinate: CLLocationCoordinate2D
    var cumulativeGroundNM: Double
    var altitudeFt: Double
    var elapsedTimeSeconds: Double
  }

  private struct SegmentResult {
    let points: [ProcedurePath.Point]
    let cumulativeNM: Double
    let altitudeFt: Double
    let elapsedTimeSeconds: Double
    let lastCoord: CLLocationCoordinate2D
  }

  /// Wraps first/second climb segments and determines which profile to use at each step.
  private struct ClimbSegments {
    let first: ClimbProfile.ProfileType
    let second: ClimbProfile.ProfileType?
    let transitionTimeSec: Double?
    let transitionAltFt: Double?

    init(schedule: ClimbSchedule) {
      self.first = schedule.firstSegment
      self.second = schedule.secondSegment
      switch schedule.transition {
        case .time(let t):
          self.transitionTimeSec = t.converted(to: .seconds).value
          self.transitionAltFt = nil
        case .altitude(let a):
          self.transitionTimeSec = nil
          self.transitionAltFt = a.converted(to: .feet).value
        case nil:
          self.transitionTimeSec = nil
          self.transitionAltFt = nil
      }
    }

    func activeProfile(elapsedSeconds: Double, altitudeFt: Double) -> ClimbProfile.ProfileType {
      guard let second else { return first }
      if let transitionTimeSec, elapsedSeconds >= transitionTimeSec {
        return second
      }
      if let transitionAltFt, altitudeFt >= transitionAltFt {
        return second
      }
      return first
    }
  }

  // MARK: - Strategy Types

  /// Resolves a procedure leg into a `ResolvedSegment` for the step engines.
  private protocol LegStrategy {
    func resolve(
      leg: Leg,
      previousCoord: CLLocationCoordinate2D,
      currentAltitudeFt: Double,
      isLast: Bool,
      variation: Measurement<UnitAngle>
    ) -> ResolvedSegment?
  }

  /// Fix-terminated legs: fly direct to the fix coordinate.
  private struct FixTerminatedStrategy: LegStrategy {
    func resolve(
      leg: Leg,
      previousCoord: CLLocationCoordinate2D,
      currentAltitudeFt _: Double,
      isLast _: Bool,
      variation _: Measurement<UnitAngle>
    ) -> ResolvedSegment? {
      guard let fixCoord = leg.coordinate else { return nil }
      return .linear(
        from: previousCoord,
        direction: .directTo(target: fixCoord),
        termination: .fix(target: fixCoord)
      )
    }
  }

  /// Hold patterns and procedure turns: only plottable as the terminal leg.
  private struct TerminalOnlyStrategy: LegStrategy {
    func resolve(
      leg: Leg,
      previousCoord: CLLocationCoordinate2D,
      currentAltitudeFt _: Double,
      isLast: Bool,
      variation _: Measurement<UnitAngle>
    ) -> ResolvedSegment? {
      guard isLast, let fixCoord = leg.coordinate else { return nil }
      return .linear(
        from: previousCoord,
        direction: .directTo(target: fixCoord),
        termination: .fix(target: fixCoord)
      )
    }
  }

  /// *ToAltitude legs: fly a course or heading until reaching a target altitude.
  private struct ToAltitudeStrategy: LegStrategy {
    let magnetic: Measurement<UnitAngle>
    let isHeading: Bool

    func resolve(
      leg: Leg,
      previousCoord: CLLocationCoordinate2D,
      currentAltitudeFt _: Double,
      isLast _: Bool,
      variation: Measurement<UnitAngle>
    ) -> ResolvedSegment? {
      let trueDeg = magnetic.toTrue(variation: variation)
        .converted(to: .degrees).value
      guard
        let targetAltitudeFt = ProcedurePathGenerator.extractTargetAltitude(
          from: leg.altitudeRestriction
        )
      else {
        return nil
      }
      let direction: DirectionMode =
        isHeading
        ? .heading(trueHeading: trueDeg)
        : .course(trueBearing: trueDeg)
      return .linear(
        from: previousCoord,
        direction: direction,
        termination: .altitude(targetFt: targetAltitudeFt)
      )
    }
  }

  /// DME-terminated legs: fly a course or heading until reaching a DME distance.
  private struct ToDMEStrategy: LegStrategy {
    let magnetic: Measurement<UnitAngle>
    let isHeading: Bool

    func resolve(
      leg: Leg,
      previousCoord: CLLocationCoordinate2D,
      currentAltitudeFt: Double,
      isLast _: Bool,
      variation: Measurement<UnitAngle>
    ) -> ResolvedSegment? {
      guard let navaid = leg.navaid,
        let dmeDistance = leg.dmeDistance
      else { return nil }
      let trueDeg = magnetic.toTrue(variation: variation)
        .converted(to: .degrees).value
      let targetGroundNM = ProcedurePathGenerator.groundDistanceFromDME(
        slantRangeNM: dmeDistance.converted(to: .nauticalMiles).value,
        aircraftAltitudeFt: currentAltitudeFt,
        navaidElevation: navaid.elevation
      )
      let direction: DirectionMode =
        isHeading
        ? .heading(trueHeading: trueDeg)
        : .course(trueBearing: trueDeg)
      return .linear(
        from: previousCoord,
        direction: direction,
        termination: .dme(reference: navaid.coordinate, targetGroundNM: targetGroundNM)
      )
    }
  }

  /// Track from fix to a DME or ground distance termination.
  private struct TrackFromFixStrategy: LegStrategy {
    let magnetic: Measurement<UnitAngle>
    let useDME: Bool

    func resolve(
      leg: Leg,
      previousCoord _: CLLocationCoordinate2D,
      currentAltitudeFt: Double,
      isLast _: Bool,
      variation: Measurement<UnitAngle>
    ) -> ResolvedSegment? {
      guard let fixCoord = leg.coordinate else { return nil }
      let trueDeg = magnetic.toTrue(variation: variation)
        .converted(to: .degrees).value

      if useDME {
        guard let navaid = leg.navaid,
          let dmeDistance = leg.dmeDistance
        else { return nil }
        let targetGroundNM = ProcedurePathGenerator.groundDistanceFromDME(
          slantRangeNM: dmeDistance.converted(to: .nauticalMiles).value,
          aircraftAltitudeFt: currentAltitudeFt,
          navaidElevation: navaid.elevation
        )
        return .linear(
          from: fixCoord,
          direction: .course(trueBearing: trueDeg),
          termination: .dme(reference: navaid.coordinate, targetGroundNM: targetGroundNM)
        )
      }
      guard let distance = leg.dmeDistance else { return nil }
      let distanceNM = distance.converted(to: .nauticalMiles).value
      return .linear(
        from: fixCoord,
        direction: .course(trueBearing: trueDeg),
        termination: .groundDistance(origin: fixCoord, targetNM: distanceNM)
      )
    }
  }

  /// Arc legs: radiusToFix and arcToFix.
  private struct ArcStrategy: LegStrategy {
    let arcRadius: Measurement<UnitLength>
    let magnetic: Measurement<UnitAngle>
    let isRadiusToFix: Bool

    func resolve(
      leg: Leg,
      previousCoord: CLLocationCoordinate2D,
      currentAltitudeFt _: Double,
      isLast _: Bool,
      variation: Measurement<UnitAngle>
    ) -> ResolvedSegment? {
      guard let legCoord = leg.coordinate else { return nil }
      let trueCourse = magnetic.toTrue(variation: variation)
      let reciprocal = trueCourse.reciprocal

      let center: CLLocationCoordinate2D
      let startAngle: Double
      let endAngle: Double

      if isRadiusToFix {
        center = GeoCalculations.destination(
          from: previousCoord,
          distance: arcRadius,
          bearing: reciprocal
        )
        startAngle = trueCourse.converted(to: .degrees).value
        endAngle =
          GeoCalculations.bearing(from: center, to: legCoord)
          .converted(to: .degrees).value
      } else {
        center = GeoCalculations.destination(
          from: legCoord,
          distance: arcRadius,
          bearing: reciprocal
        )
        endAngle = trueCourse.converted(to: .degrees).value
        startAngle = (endAngle + 180).truncatingRemainder(dividingBy: 360)
      }

      return .arc(
        from: previousCoord,
        center: center,
        radiusNM: arcRadius.converted(to: .nauticalMiles).value,
        startAngleDeg: startAngle,
        endAngleDeg: endAngle,
        targetCoord: legCoord
      )
    }
  }
}
