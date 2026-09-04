import Defaults
import SF50_Shared
import SwiftUI

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
      .font(.subheadline)
      .foregroundColor(.secondary)
    }
  }
}

#Preview {
  List {
    RwyCCWarningView()
  }
}
