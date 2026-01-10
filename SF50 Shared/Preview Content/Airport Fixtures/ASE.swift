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
      let rwy15 = Runway(
        name: "15",
        elevation: .init(value: 7680, unit: .feet),
        trueHeading: .init(value: 160, unit: .degrees),
        gradient: 0.0197,  // ~158 ft rise over 8006 ft
        length: .init(value: 8006, unit: .feet),
        width: .init(value: 100, unit: .feet),
        takeoffRun: .init(value: 7006, unit: .feet),
        takeoffDistance: .init(value: 7006, unit: .feet),
        landingDistance: .init(value: 7006, unit: .feet),
        isTurf: false,
        thresholdCoordinate: CLLocationCoordinate2D(
          latitude: 39.232176,
          longitude: -106.873148
        ),
        airport: airport
      )

      let rwy33 = Runway(
        name: "33",
        elevation: .init(value: 7838, unit: .feet),
        trueHeading: .init(value: 340, unit: .degrees),
        gradient: -0.0197,  // Downslope from 33 threshold
        length: .init(value: 8006, unit: .feet),
        width: .init(value: 100, unit: .feet),
        takeoffRun: .init(value: 8006, unit: .feet),
        takeoffDistance: .init(value: 8006, unit: .feet),
        landingDistance: .init(value: 7006, unit: .feet),  // 1000 ft displaced threshold
        isTurf: false,
        thresholdCoordinate: CLLocationCoordinate2D(
          latitude: 39.211414,
          longitude: -106.863320
        ),
        airport: airport
      )

      rwy15.reciprocal = rwy33
      rwy33.reciprocal = rwy15

      return [rwy15, rwy33]
    }
  )
}
