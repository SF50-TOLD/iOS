import Defaults
import SF50_Shared
import SwiftUI

struct SettingsView: View {
  private static let defaultSafetyFactorDry = 1.67
  private static let defaultSafetyFactorWet = 1.92

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

  @Default(.safetyFactorWet)
  private var safetyFactorWet

  @Default(.useAirportLocalTime)
  private var useAirportLocalTime

  @Default(.weightUnit)
  private var weightUnit

  @Default(.fuelDensityUnit)
  private var fuelDensityUnit

  private var hasDefaultFactors: Bool {
    safetyFactorDry == Self.defaultSafetyFactorDry
      && safetyFactorWet == Self.defaultSafetyFactorWet
  }

  var body: some View {
    NavigationView {
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
              .font(.system(size: 11))
              .fixedSize(horizontal: false, vertical: true)
            }
          }

          LabeledContent("Empty Weight") {
            MeasurementField(
              "Weight",
              value: $emptyWeight,
              unit: weightUnit,
              format: .weight,
              minimum: .init(value: 0, unit: weightUnit)
            )
            .accessibilityIdentifier("weightField")
          }
          LabeledContent("Fuel Density") {
            MeasurementField(
              "Density",
              value: $fuelDensity,
              unit: fuelDensityUnit,
              format: .fuelDensity,
              minimum: .init(value: 0, unit: fuelDensityUnit)
            )
            .accessibilityIdentifier("fuelDensityField")
          }
        }

        Section("Performance") {
          ModelToggleView()
          LabeledContent("Safety Factor (Dry)") {
            NumberField(
              "Factor",
              value: $safetyFactorDry,
              format: .number.precision(.fractionLength(0...2)),
              minimum: 1.0
            )
            .multilineTextAlignment(.trailing)
            .accessibilityIdentifier("safetyFactorDryField")
          }
          LabeledContent("Safety Factor (Wet)") {
            NumberField(
              "Factor",
              value: $safetyFactorWet,
              format: .number.precision(.fractionLength(0...2)),
              minimum: 1.0
            )
            .multilineTextAlignment(.trailing)
            .accessibilityIdentifier("safetyFactorWetField")
          }

          Button("Use AFM Safety Factors") {
            safetyFactorDry = Self.defaultSafetyFactorDry
            safetyFactorWet = Self.defaultSafetyFactorWet
          }
          .disabled(hasDefaultFactors)
          .accessibilityIdentifier("useDefaultFactorsButton")
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
    }.navigationViewStyle(navigationStyle)
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
