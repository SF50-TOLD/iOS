import Defaults
import Foundation
import SF50_Shared

/// Generates a complete takeoff TLR report as HTML.
///
/// This function orchestrates the TLR generation pipeline:
/// 1. Creates ``TakeoffReportData`` to calculate performance
/// 2. Calls `generate()` to compute all runway and scenario results
/// 3. Creates ``TakeoffReportTemplate`` to render to HTML and name the document
///
/// - Parameters:
///   - input: Aircraft, weather, and runway configuration
///   - scenarios: What-if scenarios to calculate (includes "Forecast Conditions")
/// - Returns: The rendered report and the name it carries when shared
func generateTakeoffReport(input: PerformanceInput, scenarios: [PerformanceScenario]) throws
  -> Report
{
  let reportData = TakeoffReportData(input: input, scenarios: scenarios)
  let output = try reportData.generate()

  let useAirportLocalTime = Defaults[.useAirportLocalTime]
  let template = TakeoffReportTemplate(input: input, useAirportLocalTime: useAirportLocalTime)
  return .init(
    html: template.render(runways: output.runwayInfo, scenarios: output.scenarios),
    documentTitle: template.documentTitle()
  )
}

/// Generates a complete landing TLR report as HTML.
///
/// This function orchestrates the TLR generation pipeline:
/// 1. Creates ``LandingReportData`` to calculate performance
/// 2. Calls `generate()` to compute all runway and scenario results
/// 3. Creates ``LandingReportTemplate`` to render to HTML and name the document
///
/// - Parameters:
///   - input: Aircraft, weather, and runway configuration
///   - scenarios: What-if scenarios to calculate (includes "Forecast Conditions")
/// - Returns: The rendered report and the name it carries when shared
func generateLandingReport(input: PerformanceInput, scenarios: [PerformanceScenario]) throws
  -> Report
{
  let reportData = LandingReportData(input: input, scenarios: scenarios)
  let output = try reportData.generate()

  let useAirportLocalTime = Defaults[.useAirportLocalTime]
  let template = LandingReportTemplate(input: input, useAirportLocalTime: useAirportLocalTime)
  return .init(
    html: template.render(runways: output.runwayInfo, scenarios: output.scenarios),
    documentTitle: template.documentTitle()
  )
}

/// Formats a flap setting for display, with optional short form.
func format(flapSetting setting: FlapSetting, short: Bool = false) -> String {
  if short {
    switch setting {
      case .flapsUp: return String(localized: "Up")
      case .flapsUpIce: return String(localized: "Up ICE")
      case .flaps50: return String(localized: "50")
      case .flaps50Ice: return String(localized: "50 ICE")
      case .flaps100: return String(localized: "100")
    }
  } else {
    switch setting {
      case .flapsUp: return String(localized: "Flaps Up")
      case .flapsUpIce: return String(localized: "Flaps Up ICE")
      case .flaps50: return String(localized: "Flaps 50")
      case .flaps50Ice: return String(localized: "Flaps 50 ICE")
      case .flaps100: return String(localized: "Flaps 100")
    }
  }
}
