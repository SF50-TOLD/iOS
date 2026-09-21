import SF50_Shared
import SwiftUI

/// Why a procedure's terrain profile could not be plotted, in terms a pilot can act on.
///
/// A path stops the moment the climb model has no gradient, and until now every reason read the
/// same: "the path could not be computed". Conditions the charts never covered and a hole in the
/// charts are different problems — the first is answered by flying the procedure at a weight or
/// temperature the book covers, the second cannot be answered at all — so they are told apart.
enum PathFailure {

  /// The climb model answered for every altitude, so whatever stopped the path was the
  /// procedure's own geometry rather than the performance data.
  case procedure

  /// The conditions at `altitude` sit off the end of the climb charts.
  case outsideCharts(altitude: Measurement<UnitLength>)

  /// The charts cover the conditions at `altitude` but carry no figure there.
  case chartGap(altitude: Measurement<UnitLength>)

  /// The title the section shows.
  var title: LocalizedStringKey {
    switch self {
      case .procedure: "Unable to Plot"
      case .outsideCharts: "Outside the Charts"
      case .chartGap: "No Climb Data"
    }
  }

  /// What the section says under the title.
  var message: Text {
    switch self {
      case .procedure:
        Text("The path for this procedure could not be computed.")
      case .outsideCharts(let altitude):
        Text(
          "The climb charts do not cover these conditions at \(altitude.asHeight, format: .height). Nothing is plotted above that.",
          comment: "The altitude is where the climb ran off the charts, e.g. “24,000 ft”."
        )
      case .chartGap(let altitude):
        Text(
          "The climb charts carry no figure at \(altitude.asHeight, format: .height), although they cover these conditions either side of it.",
          comment: "The altitude is where the charts have a gap, e.g. “24,000 ft”."
        )
    }
  }

  /// Reads the climb profile across the altitudes a path had to cross, and reports what stopped
  /// it.
  ///
  /// The profile is the thing that stops a path: the steppers give up exactly when it has no
  /// gradient. Where it answers for the whole band, nothing about the performance data explains
  /// the failure and the procedure itself is named instead.
  init(
    climbProfile: ClimbProfile?,
    fromAltitudeFt: Double,
    toAltitudeFt: Double,
    profile: ClimbProfile.ProfileType
  ) {
    guard let climbProfile,
      let gap = climbProfile.firstGradientGap(
        from: fromAltitudeFt,
        to: toAltitudeFt,
        profile: profile
      )
    else {
      self = .procedure
      return
    }

    let altitude = Measurement(value: gap.altitudeFt, unit: UnitLength.feet)
    switch gap.reason {
      case .offscaleLow, .offscaleHigh: self = .outsideCharts(altitude: altitude)
      default: self = .chartGap(altitude: altitude)
    }
  }
}
