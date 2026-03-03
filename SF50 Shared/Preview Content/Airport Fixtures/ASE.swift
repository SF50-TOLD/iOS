import CoreLocation
import SwiftData

extension AirportBuilder {
  public static let KASE: Self = .init(
    airport: .init(
      recordID: "ASE",
      locationID: "ASE",
      ICAO_ID: "KASE",
      name: "Aspen-Pitkin County/Sardy Field",
      city: "Aspen",
      dataSource: .NASR,
      latitude: .init(value: 39.2218783, unit: .degrees),
      longitude: .init(value: -106.8682333, unit: .degrees),
      elevation: .init(value: 7838, unit: .feet),
      variation: .init(value: -9, unit: .degrees)
    ),
    runways: { airport in
      // RWY 15: TCH 55 ft, 3.5° visual glidepath (PAPI)
      let rwy15 = Runway(
        name: "15",
        elevation: .init(value: 7737, unit: .feet),
        trueHeading: .init(value: 160, unit: .degrees),
        gradient: 0.0197,  // ~158 ft rise over 8006 ft
        length: .init(value: 8006, unit: .feet),
        width: .init(value: 100, unit: .feet),
        takeoffRun: .init(value: 7006, unit: .feet),
        takeoffDistance: .init(value: 7006, unit: .feet),
        landingDistance: .init(value: 7006, unit: .feet),
        surfaceType: .grooved,
        thresholdCoordinate: CLLocationCoordinate2D(
          latitude: 39.232174479166666,
          longitude: -106.87315104166667
        ),
        thresholdCrossingHeight: .init(value: 55, unit: .feet),
        glidepathAngle: .init(value: 3.5, unit: .degrees),
        airport: airport
      )

      // RWY 33: 1000 ft displaced threshold, no glidepath
      let rwy33 = Runway(
        name: "33",
        elevation: .init(value: 7820, unit: .feet),
        trueHeading: .init(value: 340, unit: .degrees),
        gradient: -0.0197,  // Downslope from 33 threshold
        length: .init(value: 8006, unit: .feet),
        width: .init(value: 100, unit: .feet),
        takeoffRun: .init(value: 8006, unit: .feet),
        takeoffDistance: .init(value: 8006, unit: .feet),
        landingDistance: .init(value: 7006, unit: .feet),
        surfaceType: .grooved,
        thresholdCoordinate: CLLocationCoordinate2D(
          latitude: 39.214153645833335,
          longitude: -106.8645486111111
        ),
        displacedThresholdDistance: .init(value: 1000, unit: .feet),
        airport: airport
      )

      rwy15.reciprocalName = "33"
      rwy33.reciprocalName = "15"

      return [rwy15, rwy33]
    }
  )
}
