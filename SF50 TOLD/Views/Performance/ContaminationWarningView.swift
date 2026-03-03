import Defaults
import SwiftUI

struct ContaminationWarningView: View {
  var body: some View {
    Label(
      "Contaminated runway performance data is considered supplemental and is not FAA approved. Data is primarily for runways where greater than 0.1 inch (3.0 mm) of contaminant is observed (FICON 4 or worse). Pilots/operators should recognize that these values are considered minimums and actual distances may be greater when landing in these conditions.",
      systemImage: "info.circle"
    )
    .font(.system(size: 14))
    .foregroundColor(.secondary)
  }
}

struct RwyCCWarningView: View {
  @Default(.safetyFactorDry)
  private var safetyFactorDry

  @Default(.safetyFactorWet)
  private var safetyFactorWet

  private var safetyFactorConfigured: Bool {
    safetyFactorDry != 1.0 || safetyFactorWet != 1.0
  }

  var body: some View {
    if safetyFactorConfigured {
      Label(
        "AC 91-79B landing distance factors are applied. The configured safety factor is not applied to RwyCC landing distances.",
        systemImage: "info.circle"
      )
      .font(.system(size: 14))
      .foregroundColor(.secondary)
    }
  }
}

#Preview {
  List {
    ContaminationWarningView()
    RwyCCWarningView()
  }
}
