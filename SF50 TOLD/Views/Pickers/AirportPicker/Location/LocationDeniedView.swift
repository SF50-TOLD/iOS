import SwiftUI

struct LocationDeniedView: View {
  let reason: Reason

  private var title: String {
    switch reason {
      case .app: String(localized: "Location Access Denied")
      case .deviceWide: String(localized: "Location Services Is Off")
      case .restricted: String(localized: "Location Access Restricted")
    }
  }

  private var explanation: String {
    switch reason {
      case .app:
        String(
          localized:
            "To show nearby airports, please enable location access for SF50 TOLD in Settings."
        )
      case .deviceWide:
        String(
          localized:
            "Location Services is turned off for this device. Turn it on in Settings → Privacy & Security → Location Services to see nearby airports."
        )
      case .restricted:
        String(
          localized:
            "Location access is restricted on this device, so nearby airports aren’t available. Screen Time or a device management profile usually sets this."
        )
    }
  }

  /// Settings can only lift a refusal the person owns; a restriction is set elsewhere.
  private var canOpenSettings: Bool { reason != .restricted }

  var body: some View {
    VStack(spacing: 32) {
      Text(title)
        .font(.title)
        .multilineTextAlignment(.center)

      Text(explanation)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      if canOpenSettings, let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
        Button("Open Settings") {
          UIApplication.shared.open(settingsUrl)
        }
      }
    }.padding()
  }

  /// Why location is unavailable, insofar as it changes what the person can do about it.
  enum Reason {
    /// This app was denied access.
    case app
    /// Location Services is off for the whole device.
    case deviceWide
    /// Parental restrictions or device management prevent access.
    case restricted
  }
}

#Preview("Denied") {
  LocationDeniedView(reason: .app)
}

#Preview("Services Off") {
  LocationDeniedView(reason: .deviceWide)
}

#Preview("Restricted") {
  LocationDeniedView(reason: .restricted)
}
