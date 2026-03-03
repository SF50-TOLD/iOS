import CoreLocation
import SwiftData

extension AirportBuilder {
  public static let KSQL: Self = .init(
    airport: .init(
      recordID: "SQL",
      locationID: "SQL",
      ICAO_ID: "KSQL",
      name: "San Carlos Airport",
      city: "San Carlos",
      dataSource: .NASR,
      latitude: .init(value: 37.5118611, unit: .degrees),
      longitude: .init(value: -122.2495311, unit: .degrees),
      elevation: .init(value: 5.5, unit: .feet),
      variation: .init(value: -15, unit: .degrees)
    ),
    runways: { airport in
      [
        // RWY 30: TCH 25 ft, 3° visual glidepath (PAPI)
        .init(
          name: "30",
          elevation: .init(value: 5.5, unit: .feet),
          trueHeading: .init(value: 318, unit: .degrees),
          gradient: nil,
          length: .init(value: 2621, unit: .feet),
          width: .init(value: 75, unit: .feet),
          takeoffRun: nil,
          takeoffDistance: nil,
          landingDistance: nil,
          surfaceType: .paved,
          thresholdCoordinate: CLLocationCoordinate2D(
            latitude: 37.509188368055554,
            longitude: -122.24651041666667
          ),
          thresholdCrossingHeight: .init(value: 25, unit: .feet),
          glidepathAngle: .init(value: 3.0, unit: .degrees),
          airport: airport
        ),
        // RWY 12: TCH 25 ft, 3° visual glidepath (PAPI)
        .init(
          name: "12",
          elevation: .init(value: 5.5, unit: .feet),
          trueHeading: .init(value: 138, unit: .degrees),
          gradient: nil,
          length: .init(value: 2621, unit: .feet),
          width: .init(value: 75, unit: .feet),
          takeoffRun: nil,
          takeoffDistance: nil,
          landingDistance: nil,
          surfaceType: .paved,
          thresholdCoordinate: CLLocationCoordinate2D(
            latitude: 37.51453559027778,
            longitude: -122.25255208333333
          ),
          thresholdCrossingHeight: .init(value: 25, unit: .feet),
          glidepathAngle: .init(value: 3.0, unit: .degrees),
          airport: airport
        )
      ]
    }
  )
}
