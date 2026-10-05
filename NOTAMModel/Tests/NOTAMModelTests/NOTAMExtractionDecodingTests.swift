import Foundation
import Testing

import NOTAMModel

struct NOTAMExtractionDecodingTests {
  private static let exportedLabel = Data(
    """
    {"isCanceled": false, "effects": [
      {"runway": "09R", "closure": "none",
       "partialClosure": {"length": {"value": 1713, "unit": "ft"}, "end": "W"},
       "thresholdDisplacement": null,
       "declaredDistances": {"TORA": {"value": 6787, "unit": "ft"}, "LDA": null},
       "surfaceCondition": {"rwyCC": [5, 5, 3], "contaminants": [
         {"type": "drySnowOverCompactedSnow", "coveragePercent": 30,
          "depth": {"value": 0.125, "unit": "in"}}]}},
      {"runway": "27L", "closure": "landing", "partialClosure": null, "thresholdDisplacement": null,
       "declaredDistances": null, "surfaceCondition": null}
    ], "obstacles": [
      {"height": {"value": 114, "unit": "ft", "datum": "MSL"}, "distance": {"value": 2.2, "unit": \
    "nm"},
       "reference": {"kind": "ARP", "runway": null}, "direction": "WNW"},
      {"height": {"value": 572, "unit": "ft", "datum": "MSL"}, "distance": {"value": 0.62, "unit": \
    "nm"},
       "reference": {"kind": "ARP", "runway": null}, "direction": 114}
    ]}
    """.utf8
  )

  @Test
  func `decodes an exported label with every nested type and explicit nulls`() throws {
    let extraction = try JSONDecoder().decode(NOTAMExtraction.self, from: Self.exportedLabel)

    #expect(extraction.effects.count == 2)
    #expect(extraction.effects[0].partialClosure?.end == "W")
    #expect(extraction.effects[0].declaredDistances?.TORA == .init(value: 6787, unit: .ft))
    #expect(extraction.effects[0].declaredDistances?.LDA == nil)
    #expect(extraction.effects[1].closure == .landing)
    let contaminant = try #require(extraction.effects[0].surfaceCondition?.contaminants.first)
    #expect(contaminant.type == .drySnowOverCompactedSnow)
    #expect(contaminant.depth == .init(value: 0.125, unit: .in))
    #expect(extraction.obstacles.map(\.direction) == [.compass(.WNW), .degrees(114)])
    #expect(extraction.obstacles[0].height == .init(value: 114, unit: .ft, datum: .MSL))
  }

  @Test
  func `writes an obstacle's direction back as the schema does`() throws {
    let extraction = try JSONDecoder().decode(NOTAMExtraction.self, from: Self.exportedLabel)
    let json = try #require(String(data: try JSONEncoder().encode(extraction), encoding: .utf8))

    #expect(json.contains(#""direction":"WNW""#))
    #expect(json.contains(#""direction":114"#))
  }
}
