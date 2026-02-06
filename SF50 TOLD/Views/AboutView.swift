import Defaults
import SF50_Shared
import SwiftData
import SwiftUI

struct AboutView: View {
  private static let ourAirportsTimeout: TimeInterval = 60 * 60 * 24 * 28

  @Query private var cycles: [Cycle]

  @Default(.ourAirportsLastUpdated)
  private var ourAirportsLastUpdated

  private var nasrCycle: Cycle? {
    cycles.first { $0.dataSource == .nasr }
  }

  private var cifpCycle: Cycle? {
    cycles.first { $0.dataSource == .cifp }
  }

  private var dofCycle: Cycle? {
    cycles.first { $0.dataSource == .dof }
  }

  private var releaseVersionNumber: String {
    Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
  }

  private var buildVersionNumber: String {
    Bundle.main.infoDictionary!["CFBundleVersion"] as! String
  }

  private var ourAirportsDataIsOld: Bool {
    guard let ourAirportsLastUpdated else { return true }
    return ourAirportsLastUpdated.timeIntervalSinceNow < -Self.ourAirportsTimeout
  }

  private var terrainGeneratedAt: Date {
    TerrainManifest.bundled.generatedAt
  }

  var body: some View {
    NavigationView {
      Form {
        Section("Application") {
          LabeledContent("Aircraft") {
            Text("Cirrus SF50 Vision (G1 through G2+)")
              .bold()
          }

          LabeledContent("App Version") {
            Text(
              "\(releaseVersionNumber) (\(buildVersionNumber))",
              comment: "release version (build number)"
            )
            .bold()
          }
        }

        Section("Navigation Data") {
          CycleRow(label: "NASR Cycle", cycle: nasrCycle)
          CycleRow(label: "CIFP Cycle", cycle: cifpCycle)
          CycleRow(label: "DOF Cycle", cycle: dofCycle)

          LabeledContent("OurAirports Data") {
            if let ourAirportsLastUpdated {
              Text(ourAirportsLastUpdated, format: .dateTime.day().month().year())
                .bold()
                .foregroundStyle(ourAirportsDataIsOld ? Color.red : Color.primary)
            } else {
              Text("None loaded")
                .bold()
                .foregroundStyle(.secondary)
            }
          }

          LabeledContent("Terrain Data") {
            Text(terrainGeneratedAt, format: .dateTime.day().month().year())
              .bold()
              .foregroundStyle(.primary)
          }
        }

        Section("SF50 G1 Data Source") {
          LabeledContent("Serials") {
            Text(
              "with Cirrus Perspective Touch Avionics System and FL280 Maximum Operating Altitude"
            )
            .bold()
            .font(.system(size: 14))
          }

          LabeledContent("P/N") {
            Text("31452-001", comment: "P/N")
              .bold()
          }

          LabeledContent("Revision") {
            Text("A1 (04 Feb 2022)")
              .bold()
          }
        }

        Section("SF50 G2–G2+ Data Source") {
          LabeledContent("Serials") {
            Text(
              "with Cirrus Perspective Touch+ Avionics System and FL310 Maximum Operating Altitude"
            )
            .bold()
            .font(.system(size: 14))
          }

          LabeledContent("P/N") {
            Text("31452-002", comment: "P/N")
              .bold()
          }

          LabeledContent("Reissue") {
            Text("A (03 Mar 2025)")
              .bold()
          }
        }

        Section("Updated Thrust Schedule Data Source") {
          LabeledContent("Serials") {
            Text("26000-004 or Compliance with SB5X-72-01")
              .bold()
              .font(.system(size: 14))
          }

          LabeledContent("P/N") {
            Text("31452-111", comment: "P/N")
              .bold()
          }

          LabeledContent("Revision") {
            Text("1 (10 Feb 2022)")
              .bold()
          }
        }

        Label(
          "This app has not been approved by the FAA or by Cirrus Aircraft as an official source of performance information. Always verify performance information with official sources when using this app.",
          systemImage: "exclamationmark.triangle"
        )
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
      }.navigationTitle("About")
    }.navigationViewStyle(navigationStyle)
  }
}

private struct CycleRow: View {
  let label: String
  let cycle: Cycle?

  private var state: State {
    guard let cycle else { return .expired }
    if cycle.isNotYetActive {
      return .notYetActive
    }
    if cycle.isExpired {
      return .expired
    }
    return .active
  }

  var body: some View {
    LabeledContent(label) {
      if let cycle {
        VStack(alignment: .trailing) {
          Text(cycle.name)
            .bold()
          switch state {
            case .active:
              Text("expires \(cycle.expires, format: .dateTime.year().month().day())")
                .font(.caption)
                .foregroundStyle(.secondary)
            case .expired:
              Text("expired \(cycle.expires, format: .dateTime.year().month().day())")
                .font(.caption)
            case .notYetActive:
              Text("effective \(cycle.effective, format: .dateTime.year().month().day())")
                .font(.caption)
          }
        }
        .foregroundStyle(state.color)
      } else {
        Text("None loaded")
          .bold()
          .foregroundStyle(.secondary)
      }
    }
  }

  private enum State {
    case active, expired, notYetActive

    var color: Color {
      switch self {
        case .active: .primary
        case .expired: .red
        case .notYetActive: .yellow
      }
    }
  }
}

#Preview {
  PreviewView { helper in
    helper.insertCurrentCycle(.nasr, name: "2026-01-22")
    helper.insertExpiredCycle(.cifp, name: "AIRAC 2513")
    helper.insertFutureCycle(.dof, name: "20260215")
    Defaults[.ourAirportsLastUpdated] = nil
    return AboutView()
  }
}
