import Defaults
import MeasurementKitUI
import SF50_Shared
import SwiftUI

struct SettingsView: View {
  private static let defaultSafetyFactorDry = 1.67
  private static let defaultSafetyFactorContaminated = 1.92

  @Default(.aircraftTypeSetting)
  private var aircraftTypeSetting

  @Default(.updatedThrustSchedule)
  private var updatedThrustSchedule

  @Default(.emptyWeight)
  private var emptyWeight

  @Default(.fuelDensity)
  private var fuelDensity

  @Default(.safetyFactorDry)
  private var safetyFactorDry

  @Default(.safetyFactorContaminated)
  private var safetyFactorContaminated

  @Default(.useAirportLocalTime)
  private var useAirportLocalTime

  @Default(.weightUnit)
  private var weightUnit

  @Default(.fuelDensityUnit)
  private var fuelDensityUnit

  private var hasDefaultFactors: Bool {
    safetyFactorDry == Self.defaultSafetyFactorDry
      && safetyFactorContaminated == Self.defaultSafetyFactorContaminated
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Aircraft") {
          Picker("Aircraft Model", selection: aircraftTypeSettingBinding) {
            Text("G1").tag(AircraftTypeSetting.g1)
            Text("G2").tag(AircraftTypeSetting.g2)
            Text("G2+").tag(AircraftTypeSetting.g2Plus)
          }
          .accessibilityIdentifier("aircraftTypePicker")

          if aircraftTypeSetting == .g2 {
            VStack(alignment: .leading) {
              Toggle("Use Updated Thrust Schedule", isOn: $updatedThrustSchedule)
                .accessibilityIdentifier("updatedThrustScheduleToggle")
              Text(
                "Turn this setting on if your Vision Jet has SB5X-72-01 completed (G2+ equivalent)."
              )
              .font(.footnote)
              .fixedSize(horizontal: false, vertical: true)
            }
          }

          LabeledContent("Empty Weight") {
            MeasurementField(
              "Weight",
              value: $emptyWeight,
              in: weightUnit,
              format: .weight,
              minimum: .init(value: 0, unit: weightUnit)
            )
            .accessibilityIdentifier("weightField")
          }
          LabeledContent("Fuel Density") {
            MeasurementField(
              "Density",
              value: $fuelDensity,
              in: fuelDensityUnit,
              format: .fuelDensity,
              minimum: .init(value: 0, unit: fuelDensityUnit)
            )
            .accessibilityIdentifier("fuelDensityField")
          }
        }

        Section("Performance") {
          ModelToggleView()
        }

        Section {
          LabeledContent("Dry") {
            NumericField(
              "Factor",
              value: $safetyFactorDry,
              format: .number.precision(.fractionLength(0...2)),
              minimum: 1.0
            )
            .accessibilityIdentifier("safetyFactorDryField")
          }
          LabeledContent("Contaminated") {
            NumericField(
              "Factor",
              value: $safetyFactorContaminated,
              format: .number.precision(.fractionLength(0...2)),
              minimum: 1.0
            )
            .accessibilityIdentifier("safetyFactorContaminatedField")
          }

          Button("Use AFM Safety Factors") {
            safetyFactorDry = Self.defaultSafetyFactorDry
            safetyFactorContaminated = Self.defaultSafetyFactorContaminated
          }
          .disabled(hasDefaultFactors)
          .accessibilityIdentifier("useDefaultFactorsButton")
        } header: {
          Text("Safety Factors")
        } footer: {
          Text(
            "A wet runway takes the dry factor on top of the AFM’s 15% wet-runway increase. The contaminated factor applies to standing water, slush, and snow."
          )
        }

        Section {
          NavigationLink("Takeoff/Landing Scenarios…", destination: ScenariosSettingsView())
            .accessibilityIdentifier("scenariosNavigationLink")
        }

        Section("Display") {
          NavigationLink("Units…", destination: UnitsSettingsView())
            .accessibilityIdentifier("unitsNavigationLink")
          Picker("Time Zone Display", selection: $useAirportLocalTime) {
            Text("UTC").tag(false)
            Text("Airport Local").tag(true)
          }
          .accessibilityIdentifier("timeZoneDisplayPicker")
        }

        Section("Data") {
          NavigationLink("Terrain Data…", destination: TerrainSettingsView())
            .accessibilityIdentifier("terrainNavigationLink")
        }
      }.navigationTitle("Settings")
    }
  }

  private var aircraftTypeSettingBinding: Binding<AircraftTypeSetting> {
    Binding(
      get: { aircraftTypeSetting ?? .g2 },
      set: { newValue in
        aircraftTypeSetting = newValue
        switch newValue {
          case .g1: updatedThrustSchedule = false
          case .g2: break  // Keep current updatedThrustSchedule setting
          case .g2Plus: updatedThrustSchedule = true
        }
      }
    )
  }
}

#Preview {
  SettingsView()
}
