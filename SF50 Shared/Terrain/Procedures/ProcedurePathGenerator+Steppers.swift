import CoreLocation
import Foundation
import NavData

extension ProcedurePathGenerator {

  // MARK: - Stepper Config

  /// Shared immutable context for both step engines.
  struct StepperConfig {
    let climbProfile: ClimbProfile
    let segments: ClimbSegments
    let altitudeCeilingFt: Double
    let finalAltitudeRestriction: AltitudeRestriction?
    let fixName: String?
    let levelOffAltitudeFt: Double?  // soft ceiling: caps altitude but doesn't terminate stepper

    /// Looks up atmospheric and performance data at the current step state.
    func lookupAtmosphere(
      state: StepState
    ) -> (
      profile: ClimbProfile.ProfileType, gradient: Double,
      TASKts: Double, windDirectionDeg: Double, windSpeedKts: Double
    )? {
      let profile = segments.activeProfile(
        elapsedSeconds: state.elapsedTimeSeconds,
        altitudeFt: state.altitudeFt
      )
      if let gradient = climbProfile.gradient(at: state.altitudeFt, profile: profile),
        let TASKts = climbProfile.trueAirspeed(at: state.altitudeFt, profile: profile)
      {
        let windDirectionDeg = climbProfile.windDirection(at: state.altitudeFt) ?? 0
        let windSpeedKts = climbProfile.windSpeed(at: state.altitudeFt) ?? 0
        return (profile, gradient, TASKts, windDirectionDeg, windSpeedKts)
      }

      // Active profile's tabular data may be exhausted (e.g., takeoff tables cap at
      // 10,000 ft). Fall back to subsequent segments that cover higher altitudes.
      for fallback in segments.fallbackProfiles(
        elapsedSeconds: state.elapsedTimeSeconds,
        altitudeFt: state.altitudeFt
      ) {
        if let gradient = climbProfile.gradient(at: state.altitudeFt, profile: fallback),
          let TASKts = climbProfile.trueAirspeed(at: state.altitudeFt, profile: fallback)
        {
          let windDirectionDeg = climbProfile.windDirection(at: state.altitudeFt) ?? 0
          let windSpeedKts = climbProfile.windSpeed(at: state.altitudeFt) ?? 0
          return (fallback, gradient, TASKts, windDirectionDeg, windSpeedKts)
        }
      }

      return nil
    }

    /// Trapezoidal altitude integration over one step.
    func integrateAltitude(
      g1: Double,
      airStepNM: Double,
      altitudeFt: Double,
      profile: ClimbProfile.ProfileType
    ) -> Double {
      let predictedAlt = altitudeFt + g1 * airStepNM
      let g2 = climbProfile.gradient(at: predictedAlt, profile: profile) ?? g1
      return (g1 + g2) / 2.0 * airStepNM
    }

    /// GS/TAS ratio from the wind triangle for a given course bearing.
    func gsOverTAS(
      bearing: Double,
      tas: Double,
      windDir: Double,
      windSpeed: Double
    ) -> Double {
      guard windSpeed > 0 else { return 1.0 }
      let wind = GeoCalculations.windTriangle(
        trueHeading: .init(value: bearing, unit: .degrees),
        TAS_Kts: tas,
        windFromTrue: .init(value: windDir, unit: .degrees),
        windSpeedKts: windSpeed
      )
      return wind.groundSpeedKts / tas
    }
  }

  // MARK: - Segment Stepper

  /// Minimal protocol for step-engine dispatch.
  protocol SegmentStepper {
    mutating func run() -> SegmentResult?
  }

  // MARK: - Linear Stepper

  /// Step engine for all non-arc legs.
  struct LinearStepper: SegmentStepper {
    let config: StepperConfig
    var state: StepState
    let direction: DirectionMode
    let termination: TerminationCondition
    var points: [ProcedurePath.Point] = []

    /// Signed cross-track distance from a position to a course line.
    /// Positive = right of course, negative = left of course.
    private static func crossTrackSign(
      position: CLLocationCoordinate2D,
      courseTrueDeg: Double,
      pointOnCourse: CLLocationCoordinate2D
    ) -> Double {
      let bearingToPos = GeoCalculations.bearing(from: pointOnCourse, to: position)
        .converted(to: .degrees).value
      let distNM = GeoCalculations.distanceNM(from: pointOnCourse, to: position)
      let angleDiff = (bearingToPos - courseTrueDeg) * .pi / 180.0
      return distNM * sin(angleDiff)
    }

    mutating func run() -> SegmentResult? {
      for _ in 0..<ProcedurePathGenerator.maxSteps {
        guard let step = computeStep() else { return nil }
        if let result = checkCeiling(step) { return result }
        if let result = checkTermination(step) { return result }
        advance(step)
      }
      return nil
    }

    // MARK: Ground Track Resolution

    /// Resolves the ground bearing and GS/TAS ratio from the direction mode.
    private func resolveGroundTrack(
      tas: Double,
      windDir: Double,
      windSpeed: Double
    ) -> (bearing: Double, gsRatio: Double) {
      switch direction {
        case .course(let trueBearing):
          return (
            trueBearing,
            config.gsOverTAS(
              bearing: trueBearing,
              tas: tas,
              windDir: windDir,
              windSpeed: windSpeed
            )
          )

        case .heading(let trueHeading):
          if windSpeed > 0 {
            let wind = GeoCalculations.windTriangle(
              trueHeading: .init(value: trueHeading, unit: .degrees),
              TAS_Kts: tas,
              windFromTrue: .init(value: windDir, unit: .degrees),
              windSpeedKts: windSpeed
            )
            return (
              wind.groundTrack.converted(to: .degrees).value,
              wind.groundSpeedKts / tas
            )
          }
          return (trueHeading, 1.0)

        case .directTo(let target):
          let bearing = GeoCalculations.bearing(from: state.coordinate, to: target)
            .converted(to: .degrees).value
          return (
            bearing,
            config.gsOverTAS(bearing: bearing, tas: tas, windDir: windDir, windSpeed: windSpeed)
          )
      }
    }

    // MARK: Step Computation

    private func computeStep() -> Step? {
      guard let atmo = config.lookupAtmosphere(state: state) else { return nil }

      let (groundBearing, gsRatio) = resolveGroundTrack(
        tas: atmo.TASKts,
        windDir: atmo.windDirectionDeg,
        windSpeed: atmo.windSpeedKts
      )
      guard gsRatio > 0 else { return nil }

      let airStepNM = ProcedurePathGenerator.groundStepNM / gsRatio
      let groundSpeedKts = atmo.TASKts * gsRatio
      let stepTime = (ProcedurePathGenerator.groundStepNM / groundSpeedKts) * 3600

      let rawAltGain = config.integrateAltitude(
        g1: atmo.gradient,
        airStepNM: airStepNM,
        altitudeFt: state.altitudeFt,
        profile: atmo.profile
      )

      var nextAlt = state.altitudeFt + rawAltGain
      if let levelOff = config.levelOffAltitudeFt, nextAlt > levelOff {
        nextAlt = levelOff
      }
      let altGain = nextAlt - state.altitudeFt

      let nextCoord = GeoCalculations.destination(
        from: state.coordinate,
        distance: .init(value: ProcedurePathGenerator.groundStepNM, unit: .nauticalMiles),
        bearing: .init(value: groundBearing, unit: .degrees)
      )

      return Step(
        groundBearing: groundBearing,
        gsRatio: gsRatio,
        airStepNM: airStepNM,
        stepTime: stepTime,
        altGain: altGain,
        nextAlt: nextAlt,
        gradient: atmo.gradient,
        profile: atmo.profile,
        nextCoord: nextCoord
      )
    }

    // MARK: Ceiling Check

    private mutating func checkCeiling(_ step: Step) -> SegmentResult? {
      guard step.nextAlt >= config.altitudeCeilingFt else { return nil }
      let altNeeded = config.altitudeCeilingFt - state.altitudeFt
      let fraction = step.altGain > 0 ? altNeeded / step.altGain : 1.0
      let partialGroundNM = ProcedurePathGenerator.groundStepNM * fraction
      let finalCoord = GeoCalculations.destination(
        from: state.coordinate,
        distance: .init(value: partialGroundNM, unit: .nauticalMiles),
        bearing: .init(value: step.groundBearing, unit: .degrees)
      )
      let finalCumNM = state.cumulativeGroundNM + partialGroundNM
      let finalTime = state.elapsedTimeSeconds + step.stepTime * fraction

      points.append(
        .init(
          coordinate: finalCoord,
          distanceNM: finalCumNM,
          altitudeFt: config.altitudeCeilingFt,
          elapsedTimeSeconds: finalTime,
          altitudeRestriction: config.finalAltitudeRestriction,
          fixName: config.fixName
        )
      )
      return SegmentResult(
        points: points,
        cumulativeNM: finalCumNM,
        altitudeFt: config.altitudeCeilingFt,
        elapsedTimeSeconds: finalTime,
        lastCoord: finalCoord
      )
    }

    // MARK: Termination Check

    /// Applies the level-off altitude cap to a computed termination altitude.
    private func capAltitude(_ altitude: Double) -> Double {
      if let levelOff = config.levelOffAltitudeFt, altitude > levelOff {
        return levelOff
      }
      return altitude
    }

    private mutating func checkTermination(_ step: Step) -> SegmentResult? {
      switch termination {
        case .fix(let target):
          let distToTarget = GeoCalculations.distanceNM(from: state.coordinate, to: target)
          guard distToTarget <= ProcedurePathGenerator.groundStepNM else { return nil }
          let fraction =
            ProcedurePathGenerator.groundStepNM > 0
            ? distToTarget / ProcedurePathGenerator.groundStepNM : 1.0
          let partialAirNM = fraction * step.airStepNM
          let partialG2 =
            config.climbProfile.gradient(
              at: state.altitudeFt + step.gradient * partialAirNM,
              profile: step.profile
            )
            ?? step.gradient
          let partialAltGain = (step.gradient + partialG2) / 2.0 * partialAirNM
          let finalAlt = capAltitude(state.altitudeFt + partialAltGain)
          let finalCumNM = state.cumulativeGroundNM + distToTarget
          let finalTime = state.elapsedTimeSeconds + step.stepTime * fraction

          points.append(
            .init(
              coordinate: target,
              distanceNM: finalCumNM,
              altitudeFt: finalAlt,
              elapsedTimeSeconds: finalTime,
              altitudeRestriction: config.finalAltitudeRestriction,
              fixName: config.fixName
            )
          )
          return SegmentResult(
            points: points,
            cumulativeNM: finalCumNM,
            altitudeFt: finalAlt,
            elapsedTimeSeconds: finalTime,
            lastCoord: target
          )

        case .altitude(let targetFt):
          guard step.nextAlt >= targetFt else { return nil }
          let altNeeded = targetFt - state.altitudeFt
          let fraction = step.altGain > 0 ? altNeeded / step.altGain : 1.0
          let partialGroundNM = ProcedurePathGenerator.groundStepNM * fraction
          let finalCoord = GeoCalculations.destination(
            from: state.coordinate,
            distance: .init(value: partialGroundNM, unit: .nauticalMiles),
            bearing: .init(value: step.groundBearing, unit: .degrees)
          )
          let finalCumNM = state.cumulativeGroundNM + partialGroundNM
          let finalTime = state.elapsedTimeSeconds + step.stepTime * fraction

          points.append(
            .init(
              coordinate: finalCoord,
              distanceNM: finalCumNM,
              altitudeFt: targetFt,
              elapsedTimeSeconds: finalTime,
              altitudeRestriction: config.finalAltitudeRestriction,
              fixName: config.fixName
            )
          )
          return SegmentResult(
            points: points,
            cumulativeNM: finalCumNM,
            altitudeFt: targetFt,
            elapsedTimeSeconds: finalTime,
            lastCoord: finalCoord
          )

        case .dme(let reference, let targetGroundNM):
          let prevDist = GeoCalculations.distanceNM(from: state.coordinate, to: reference)
          let nextDist = GeoCalculations.distanceNM(from: step.nextCoord, to: reference)
          let movingToward = prevDist > targetGroundNM

          let crossed =
            movingToward
            ? nextDist <= targetGroundNM
            : nextDist >= targetGroundNM

          guard crossed else { return nil }

          let prevDelta = abs(prevDist - targetGroundNM)
          let nextDelta = abs(nextDist - targetGroundNM)
          let totalDelta = prevDelta + nextDelta
          let fraction = totalDelta > 0 ? prevDelta / totalDelta : 0.5
          let partialGroundNM = ProcedurePathGenerator.groundStepNM * fraction
          let partialAirNM = partialGroundNM / step.gsRatio
          let partialG2 =
            config.climbProfile.gradient(
              at: state.altitudeFt + step.gradient * partialAirNM,
              profile: step.profile
            )
            ?? step.gradient
          let partialAltGain = (step.gradient + partialG2) / 2.0 * partialAirNM

          let finalCoord = GeoCalculations.destination(
            from: state.coordinate,
            distance: .init(value: partialGroundNM, unit: .nauticalMiles),
            bearing: .init(value: step.groundBearing, unit: .degrees)
          )
          let finalAlt = capAltitude(state.altitudeFt + partialAltGain)
          let finalCumNM = state.cumulativeGroundNM + partialGroundNM
          let finalTime = state.elapsedTimeSeconds + step.stepTime * fraction

          points.append(
            .init(
              coordinate: finalCoord,
              distanceNM: finalCumNM,
              altitudeFt: finalAlt,
              elapsedTimeSeconds: finalTime,
              altitudeRestriction: config.finalAltitudeRestriction,
              fixName: config.fixName
            )
          )
          return SegmentResult(
            points: points,
            cumulativeNM: finalCumNM,
            altitudeFt: finalAlt,
            elapsedTimeSeconds: finalTime,
            lastCoord: finalCoord
          )

        case .groundDistance(let origin, let targetNM):
          let currentDist = GeoCalculations.distanceNM(from: origin, to: step.nextCoord)
          guard currentDist >= targetNM else { return nil }

          let prevDist = GeoCalculations.distanceNM(from: origin, to: state.coordinate)
          let prevDelta = abs(prevDist - targetNM)
          let nextDelta = abs(currentDist - targetNM)
          let totalDelta = prevDelta + nextDelta
          let fraction = totalDelta > 0 ? prevDelta / totalDelta : 0.5
          let partialGroundNM = ProcedurePathGenerator.groundStepNM * fraction
          let partialAirNM = partialGroundNM / step.gsRatio
          let partialG2 =
            config.climbProfile.gradient(
              at: state.altitudeFt + step.gradient * partialAirNM,
              profile: step.profile
            )
            ?? step.gradient
          let partialAltGain = (step.gradient + partialG2) / 2.0 * partialAirNM

          let finalCoord = GeoCalculations.destination(
            from: state.coordinate,
            distance: .init(value: partialGroundNM, unit: .nauticalMiles),
            bearing: .init(value: step.groundBearing, unit: .degrees)
          )
          let finalAlt = capAltitude(state.altitudeFt + partialAltGain)
          let finalCumNM = state.cumulativeGroundNM + partialGroundNM
          let finalTime = state.elapsedTimeSeconds + step.stepTime * fraction

          points.append(
            .init(
              coordinate: finalCoord,
              distanceNM: finalCumNM,
              altitudeFt: finalAlt,
              elapsedTimeSeconds: finalTime,
              altitudeRestriction: config.finalAltitudeRestriction,
              fixName: config.fixName
            )
          )
          return SegmentResult(
            points: points,
            cumulativeNM: finalCumNM,
            altitudeFt: finalAlt,
            elapsedTimeSeconds: finalTime,
            lastCoord: finalCoord
          )

        case .courseIntercept(let courseTrueDeg, let pointOnCourse):
          // Compute signed cross-track distance at current and next positions.
          // The sign flips when the aircraft crosses the course line.
          let prevXTD = Self.crossTrackSign(
            position: state.coordinate,
            courseTrueDeg: courseTrueDeg,
            pointOnCourse: pointOnCourse
          )
          let nextXTD = Self.crossTrackSign(
            position: step.nextCoord,
            courseTrueDeg: courseTrueDeg,
            pointOnCourse: pointOnCourse
          )

          // Sign flip (or landing exactly on the line) indicates crossing
          guard prevXTD * nextXTD <= 0 else { return nil }

          let absPrev = abs(prevXTD)
          let absNext = abs(nextXTD)
          let totalDelta = absPrev + absNext
          let fraction = totalDelta > 0 ? absPrev / totalDelta : 0.5
          let partialGroundNM = ProcedurePathGenerator.groundStepNM * fraction
          let partialAirNM = partialGroundNM / step.gsRatio
          let partialG2 =
            config.climbProfile.gradient(
              at: state.altitudeFt + step.gradient * partialAirNM,
              profile: step.profile
            )
            ?? step.gradient
          let partialAltGain = (step.gradient + partialG2) / 2.0 * partialAirNM

          let finalCoord = GeoCalculations.destination(
            from: state.coordinate,
            distance: .init(value: partialGroundNM, unit: .nauticalMiles),
            bearing: .init(value: step.groundBearing, unit: .degrees)
          )
          let finalAlt = capAltitude(state.altitudeFt + partialAltGain)
          let finalCumNM = state.cumulativeGroundNM + partialGroundNM
          let finalTime = state.elapsedTimeSeconds + step.stepTime * fraction

          points.append(
            .init(
              coordinate: finalCoord,
              distanceNM: finalCumNM,
              altitudeFt: finalAlt,
              elapsedTimeSeconds: finalTime,
              altitudeRestriction: config.finalAltitudeRestriction,
              fixName: config.fixName
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

    // MARK: Advance

    private mutating func advance(_ step: Step) {
      let nextCumulativeNM = state.cumulativeGroundNM + ProcedurePathGenerator.groundStepNM
      let nextElapsedTime = state.elapsedTimeSeconds + step.stepTime

      state.coordinate = step.nextCoord
      state.cumulativeGroundNM = nextCumulativeNM
      state.altitudeFt = step.nextAlt
      state.elapsedTimeSeconds = nextElapsedTime

      points.append(
        .init(
          coordinate: step.nextCoord,
          distanceNM: nextCumulativeNM,
          altitudeFt: step.nextAlt,
          elapsedTimeSeconds: nextElapsedTime
        )
      )
    }

    /// Per-step derived values, bundled to avoid passing many arguments.
    private struct Step {
      let groundBearing: Double
      let gsRatio: Double
      let airStepNM: Double
      let stepTime: Double
      let altGain: Double
      let nextAlt: Double
      let gradient: Double
      let profile: ClimbProfile.ProfileType
      let nextCoord: CLLocationCoordinate2D
    }
  }

  // MARK: - Arc Stepper

  /// Step engine for radiusToFix and arcToFix legs.
  struct ArcStepper: SegmentStepper {
    let config: StepperConfig
    let center: CLLocationCoordinate2D
    let radiusNM: Double
    let sweep: Double
    let actualStepDeg: Double
    let stepCount: Int
    let startAngleDeg: Double
    let targetCoord: CLLocationCoordinate2D
    var state: StepState
    var points: [ProcedurePath.Point] = []

    init(
      config: StepperConfig,
      state: StepState,
      center: CLLocationCoordinate2D,
      radiusNM: Double,
      startAngleDeg: Double,
      endAngleDeg: Double,
      targetCoord: CLLocationCoordinate2D
    ) {
      self.config = config
      self.state = state
      self.center = center
      self.radiusNM = radiusNM
      self.targetCoord = targetCoord
      self.startAngleDeg = startAngleDeg

      var sweep = endAngleDeg - startAngleDeg
      if sweep > 180 { sweep -= 360 }
      if sweep < -180 { sweep += 360 }
      self.sweep = sweep

      let stepDeg = (ProcedurePathGenerator.groundStepNM / radiusNM) * (180.0 / .pi)
      let count = max(1, Int(abs(sweep) / stepDeg))
      self.stepCount = count
      self.actualStepDeg = sweep / Double(count)
    }

    mutating func run() -> SegmentResult? {
      guard abs(sweep) > 0 else { return nil }

      var currentAngle = startAngleDeg

      for i in 1...stepCount {
        guard let step = computeArcStep(index: i, currentAngle: currentAngle) else { return nil }
        if let result = advance(step, isLast: i == stepCount) { return result }
        currentAngle = startAngleDeg + actualStepDeg * Double(i)
      }

      return SegmentResult(
        points: points,
        cumulativeNM: state.cumulativeGroundNM,
        altitudeFt: state.altitudeFt,
        elapsedTimeSeconds: state.elapsedTimeSeconds,
        lastCoord: state.coordinate
      )
    }

    // MARK: Arc Step Computation

    private func computeArcStep(index: Int, currentAngle: Double) -> ArcStep? {
      guard let atmo = config.lookupAtmosphere(state: state) else { return nil }

      let nextAngle = startAngleDeg + actualStepDeg * Double(index)
      let normalizedAngle = nextAngle.normalizedAngle
      let isLast = index == stepCount

      let nextCoord: CLLocationCoordinate2D
      if isLast {
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

      let gsRatio = config.gsOverTAS(
        bearing: tangentBearing,
        tas: atmo.TASKts,
        windDir: atmo.windDirectionDeg,
        windSpeed: atmo.windSpeedKts
      )
      guard gsRatio > 0 else { return nil }

      let airStepNM = segGroundNM / gsRatio
      let groundSpeedKts = atmo.TASKts * gsRatio
      let segTime = groundSpeedKts > 0 ? (segGroundNM / groundSpeedKts) * 3600 : 0

      let altGain = config.integrateAltitude(
        g1: atmo.gradient,
        airStepNM: airStepNM,
        altitudeFt: state.altitudeFt,
        profile: atmo.profile
      )

      return ArcStep(
        nextCoord: nextCoord,
        segGroundNM: segGroundNM,
        altGain: altGain,
        segTime: segTime
      )
    }

    // MARK: Arc Advance

    /// Updates state and emits a point; returns a result early if the ceiling is hit.
    private mutating func advance(_ step: ArcStep, isLast: Bool) -> SegmentResult? {
      state.coordinate = step.nextCoord
      state.cumulativeGroundNM += step.segGroundNM
      state.altitudeFt += step.altGain
      state.elapsedTimeSeconds += step.segTime

      // Apply level-off cap (soft ceiling)
      if let levelOff = config.levelOffAltitudeFt, state.altitudeFt > levelOff {
        state.altitudeFt = levelOff
      }

      // Check altitude ceiling
      if state.altitudeFt >= config.altitudeCeilingFt {
        state.altitudeFt = config.altitudeCeilingFt
        points.append(
          .init(
            coordinate: step.nextCoord,
            distanceNM: state.cumulativeGroundNM,
            altitudeFt: config.altitudeCeilingFt,
            elapsedTimeSeconds: state.elapsedTimeSeconds,
            altitudeRestriction: config.finalAltitudeRestriction,
            fixName: config.fixName
          )
        )
        return SegmentResult(
          points: points,
          cumulativeNM: state.cumulativeGroundNM,
          altitudeFt: config.altitudeCeilingFt,
          elapsedTimeSeconds: state.elapsedTimeSeconds,
          lastCoord: step.nextCoord
        )
      }

      points.append(
        .init(
          coordinate: step.nextCoord,
          distanceNM: state.cumulativeGroundNM,
          altitudeFt: state.altitudeFt,
          elapsedTimeSeconds: state.elapsedTimeSeconds,
          altitudeRestriction: isLast ? config.finalAltitudeRestriction : nil,
          fixName: isLast ? config.fixName : nil
        )
      )
      return nil
    }

    /// Per-step derived values for an arc segment.
    private struct ArcStep {
      let nextCoord: CLLocationCoordinate2D
      let segGroundNM: Double
      let altGain: Double
      let segTime: Double
    }
  }
}
