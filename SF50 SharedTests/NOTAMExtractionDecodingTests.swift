import Foundation
import Testing

@testable import SF50_Shared

struct NOTAMExtractionDecodingTests {
  private static let exportedLabel = Data(
    """
    {"isCanceled": false, "effects": [
      {"runway": null, "closure": "none", "closedLength": null, "closedEnd": null,
       "thresholdDisplacement": null, "declaredDistances": null, "surfaceCondition": null,
       "obstacle": {"heightAGL": {"value": 100, "unit": "ft"}, "heightMSL": {"value": 122, "unit": \
    "ft"},
                    "distance": {"value": 2.3, "unit": "nm"}, "distanceReference": "JFK",
                    "bearingDegrees": null, "latitude": 40.653611, "longitude": -73.825833}},
      {"runway": "09R", "closure": "none", "closedLength": null, "closedEnd": null,
       "thresholdDisplacement": null,
       "declaredDistances": {"TORA": {"value": 6787, "unit": "ft"}, "TODA": null, "ASDA": null, \
    "LDA": null},
       "surfaceCondition": null, "obstacle": null},
      {"runway": "09R/27L", "closure": "partial", "closedLength": {"value": 1713, "unit": "ft"},
       "closedEnd": "W", "thresholdDisplacement": null, "declaredDistances": null,
       "surfaceCondition": {"rwyCC": [5, 5, 3], "contaminants": [
         {"type": "drySnowOverCompactedSnow", "runwayThird": 1, "coveragePercent": 30,
          "depth": {"value": 0.125, "unit": "in"}}]},
       "obstacle": null}
    ]}
    """.utf8
  )

  @Test
  func `decodes an exported label with every nested type and explicit nulls`() throws {
    let extraction = try JSONDecoder().decode(NOTAMExtraction.self, from: Self.exportedLabel)

    #expect(extraction.effects.count == 3)
    #expect(extraction.effects[0].obstacle?.heightMSL == .init(value: 122, unit: .ft))
    #expect(extraction.effects[1].declaredDistances?.TORA == .init(value: 6787, unit: .ft))
    #expect(extraction.effects[1].declaredDistances?.LDA == nil)
    #expect(extraction.effects[2].closure == .partial)
    let contaminant = try #require(extraction.effects[2].surfaceCondition?.contaminants.first)
    #expect(contaminant.type == .drySnowOverCompactedSnow)
    #expect(contaminant.depth == .init(value: 0.125, unit: .in))
  }
}
