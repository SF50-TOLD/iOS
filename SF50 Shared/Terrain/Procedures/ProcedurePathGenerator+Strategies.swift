import CoreLocation
import Foundation

extension ProcedurePathGenerator {

  // MARK: - Strategy Types

  /// Resolves a procedure leg into a `ResolvedSegment` for the step engines.
  protocol LegStrategy {
    func resolve(
      leg: Leg,
      previousCoord: CLLocationCoordinate2D,
      currentAltitudeFt: Double,
      isLast: Bool,
      variation: Measurement<UnitAngle>
    ) -> ResolvedSegment?
  }

  /// Fix-terminated legs: fly direct to the fix coordinate.
  struct FixTerminatedStrategy: LegStrategy {
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
  struct TerminalOnlyStrategy: LegStrategy {
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
  struct ToAltitudeStrategy: LegStrategy {
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
  struct ToDMEStrategy: LegStrategy {
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
  struct TrackFromFixStrategy: LegStrategy {
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

  /// *ToIntercept legs: fly a course or heading until intercepting the next leg's course line.
  struct ToInterceptStrategy: LegStrategy {
    let magnetic: Measurement<UnitAngle>
    let isHeading: Bool
    let interceptCourseMagnetic: Measurement<UnitAngle>
    let pointOnCourse: CLLocationCoordinate2D

    func resolve(
      leg _: Leg,
      previousCoord: CLLocationCoordinate2D,
      currentAltitudeFt _: Double,
      isLast _: Bool,
      variation: Measurement<UnitAngle>
    ) -> ResolvedSegment? {
      let trueDeg = magnetic.toTrue(variation: variation)
        .converted(to: .degrees).value
      let interceptTrueDeg = interceptCourseMagnetic.toTrue(variation: variation)
        .converted(to: .degrees).value
      let direction: DirectionMode =
        isHeading
        ? .heading(trueHeading: trueDeg)
        : .course(trueBearing: trueDeg)
      return .linear(
        from: previousCoord,
        direction: direction,
        termination: .courseIntercept(
          courseTrueDeg: interceptTrueDeg,
          pointOnCourse: pointOnCourse
        )
      )
    }
  }

  /// *ToRadial legs: fly a course or heading until intercepting a VOR radial.
  struct ToRadialStrategy: LegStrategy {
    let magnetic: Measurement<UnitAngle>
    let isHeading: Bool

    func resolve(
      leg: Leg,
      previousCoord: CLLocationCoordinate2D,
      currentAltitudeFt _: Double,
      isLast _: Bool,
      variation: Measurement<UnitAngle>
    ) -> ResolvedSegment? {
      guard let navaid = leg.navaid,
        let theta = leg.theta
      else { return nil }
      let trueDeg = magnetic.toTrue(variation: variation)
        .converted(to: .degrees).value
      let radialTrueDeg = theta.toTrue(variation: variation)
        .converted(to: .degrees).value
      let direction: DirectionMode =
        isHeading
        ? .heading(trueHeading: trueDeg)
        : .course(trueBearing: trueDeg)
      return .linear(
        from: previousCoord,
        direction: direction,
        termination: .courseIntercept(
          courseTrueDeg: radialTrueDeg,
          pointOnCourse: navaid.coordinate
        )
      )
    }
  }

  /// Arc legs: radiusToFix and arcToFix.
  struct ArcStrategy: LegStrategy {
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
