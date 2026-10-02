import Foundation
import Testing

@testable import SF50_Shared

struct GoAroundClimbGradientTests {

  // MARK: - Helpers

  private static let configurations: [(FlapSetting, landingTable: String)] = [
    (.flaps100, "100"), (.flaps50, "50"), (.flapsUp, "50")
  ]

  private static let aircraft: [AircraftType] = [
    .g1, .g2(updatedThrustSchedule: false), .g2Plus
  ]

  private func model(
    _ aircraftType: AircraftType,
    flapSetting: FlapSetting,
    weight: Double,
    elevation: Double,
    temperature: Double
  ) -> RegressionPerformanceModel {
    RegressionPerformanceModel(
      conditions: Helper.createTestConditions(temperature: temperature),
      configuration: Helper.createTestConfiguration(weight: weight, flapSetting: flapSetting),
      runway: Helper.createTestRunwayInput(elevation: elevation),
      notam: nil,
      aircraftType: aircraftType
    )
  }

  /// Every cell of a landing table's grid, and whether the AFM prints a distance there.
  private func afmCells(
    _ aircraftType: AircraftType,
    landingTable: String
  ) throws -> [(weight: Double, altitude: Double, temperature: Double, printed: Bool)] {
    let table = try DataTable(
      fileURL: Bundle(for: BasePerformanceModel.self).resourceURL!
        .appending(component: "Data/\(aircraftType.dataDirectoryName)/landing/\(landingTable)")
        .appending(component: "total distance.csv")
    )
    let printed = Set(table.rows.map { table.inputs(from: $0) })
    func axis(_ dimension: Int) -> [Double] {
      Set(printed.map { $0[dimension] }).sorted()
    }

    return axis(0).flatMap { weight in
      axis(1).flatMap { altitude in
        axis(2).map { temperature in
          (weight, altitude, temperature, printed.contains([weight, altitude, temperature]))
        }
      }
    }
  }

  // MARK: - Tests

  @Test(arguments: aircraft, configurations)
  func `the regression meets the gradient exactly where the AFM prints a landing distance`(
    aircraftType: AircraftType,
    configuration: (FlapSetting, landingTable: String)
  ) throws {
    for cell in try afmCells(aircraftType, landingTable: configuration.landingTable) {
      let meets = model(
        aircraftType,
        flapSetting: configuration.0,
        weight: cell.weight,
        elevation: cell.altitude,
        temperature: cell.temperature
      ).meetsGoAroundClimbGradient
      #expect(
        meets == .value(cell.printed),
        "\(configuration.0) at \(cell.weight) lb, \(cell.altitude) ft, \(cell.temperature) °C"
      )
    }
  }

  @Test(arguments: [FlapSetting.flaps50Ice, .flapsUpIce])
  func `in icing the gradient is met within the AFM's table and not past its hot edge`(
    flapSetting: FlapSetting
  ) {
    func meets(temperature: Double) -> Value<Bool> {
      model(
        .g2Plus,
        flapSetting: flapSetting,
        weight: 5550,
        elevation: 0,
        temperature: temperature
      ).meetsGoAroundClimbGradient
    }

    #expect(meets(temperature: 0) == .value(true))
    #expect(meets(temperature: 15) == .value(false))
  }
}
