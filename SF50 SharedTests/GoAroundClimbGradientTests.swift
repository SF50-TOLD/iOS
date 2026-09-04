import Foundation
import Testing

@testable import SF50_Shared

struct GoAroundClimbGradientTests {

  // MARK: - Helper

  private func buildModel(
    weight: Double = 6000,
    elevation: Double = 0,
    temperature: Double = 15
  ) -> RegressionPerformanceModel {
    let conditions = Helper.createTestConditions(temperature: temperature)
    let configuration = Helper.createTestConfiguration(weight: weight)
    let runway = Helper.createTestRunwayInput(elevation: elevation)
    return RegressionPerformanceModel(
      conditions: conditions,
      configuration: configuration,
      runway: runway,
      notam: nil,
      aircraftType: .g2(updatedThrustSchedule: false)
    )
  }

  private func meetsGradient(
    weight: Double = 6000,
    elevation: Double = 0,
    temperature: Double = 15
  ) -> Bool? {
    let model = buildModel(weight: weight, elevation: elevation, temperature: temperature)
    if case .value(let meets) = model.meetsGoAroundClimbGradient {
      return meets
    }
    return nil
  }

  // MARK: - Standard Conditions

  @Test
  func `standard conditions pass`() {
    let meets = meetsGradient(weight: 5000, elevation: 0, temperature: 15)
    #expect(meets == true)
  }

  // MARK: - Extreme Conditions

  @Test
  func `extreme hot high heavy fails`() {
    let meets = meetsGradient(weight: 6000, elevation: 8000, temperature: 40)
    #expect(meets == false)
  }

  // MARK: - Boundary Behavior

  @Test
  func `boundary behavior`() {
    // Near the decision boundary: barely passes (probability ~0.56)
    let barelyPasses = meetsGradient(weight: 5800, elevation: 7000, temperature: 35)
    #expect(barelyPasses == true)

    // Slightly worse conditions push below the threshold (probability ~0.48)
    let barelyFails = meetsGradient(weight: 5800, elevation: 7500, temperature: 35)
    #expect(barelyFails == false)
  }

  // MARK: - Weight Sensitivity

  @Test
  func `light weight passes at high altitude`() {
    let meets = meetsGradient(weight: 4500, elevation: 6000, temperature: 30)
    #expect(meets == true)
  }

  @Test
  func `heavy weight fails at high altitude`() {
    let meets = meetsGradient(weight: 6000, elevation: 6000, temperature: 40)
    #expect(meets == false)
  }

  // MARK: - Temperature Sensitivity

  @Test
  func `cool temperature passes`() {
    let meets = meetsGradient(weight: 5500, elevation: 5000, temperature: 0)
    #expect(meets == true)
  }

  @Test
  func `very hot temperature fails`() {
    let meets = meetsGradient(weight: 5500, elevation: 7000, temperature: 45)
    #expect(meets == false)
  }

  // MARK: - Altitude Sensitivity

  @Test
  func `low altitude passes`() {
    let meets = meetsGradient(weight: 5500, elevation: 0, temperature: 30)
    #expect(meets == true)
  }

  @Test
  func `high altitude fails`() {
    let meets = meetsGradient(weight: 5500, elevation: 9000, temperature: 30)
    #expect(meets == false)
  }
}
