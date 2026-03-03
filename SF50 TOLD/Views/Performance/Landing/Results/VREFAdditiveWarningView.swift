import SwiftUI

struct VREFAdditiveWarningView: View {
  var body: some View {
    Label(
      "Landing distances include an AC 91-79B §5.2.2 adjustment for the VREF additive. This additive is an approximation.",
      systemImage: "info.circle"
    )
    .font(.system(size: 14))
    .foregroundColor(.secondary)
  }
}

#Preview {
  List {
    VREFAdditiveWarningView()
  }
}
