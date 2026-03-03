import CoreLocation
import Foundation
import SwiftData

extension AirportBuilder {
  public static let KOAK: Self = .init(
    airport: .init(
      recordID: "OAK",
      locationID: "OAK",
      ICAO_ID: "KOAK",
      name: "San Francisco Bay Area Metropolitan Oakland International Airport",
      city: "Oakland",
      dataSource: .NASR,
      latitude: .init(value: 37.7212614, unit: .degrees),
      longitude: .init(value: -122.2211506, unit: .degrees),
      elevation: .init(value: 9, unit: .feet),
      variation: .init(value: -14, unit: .degrees)
    ),
    runways: { airport in
      [
        // RWY 12: TCH 70 ft, ~2.75° visual glidepath (PAPI)
        .init(
          name: "12",
          elevation: .init(value: 8.6, unit: .feet),
          trueHeading: .init(value: 130, unit: .degrees),
          gradient: nil,
          length: .init(value: 10520, unit: .feet),
          width: .init(value: 150, unit: .feet),
          takeoffRun: .init(value: 10000, unit: .feet),
          takeoffDistance: .init(value: 10000, unit: .feet),
          landingDistance: .init(value: 10000, unit: .feet),
          surfaceType: .grooved,
          thresholdCoordinate: CLLocationCoordinate2D(
            latitude: 37.72006076388889,
            longitude: -122.24211805555555
          ),
          thresholdCrossingHeight: .init(value: 70, unit: .feet),
          glidepathAngle: .init(value: 2.75, unit: .degrees),
          airport: airport
        ),
        // ILS RWY 30: TCH 71 ft, 3° glideslope, 114 ft displaced threshold
        .init(
          name: "30",
          elevation: .init(value: 9, unit: .feet),
          trueHeading: .init(value: 310, unit: .degrees),
          gradient: nil,
          length: .init(value: 10520, unit: .feet),
          width: .init(value: 150, unit: .feet),
          takeoffRun: .init(value: 10000, unit: .feet),
          takeoffDistance: .init(value: 10000, unit: .feet),
          landingDistance: .init(value: 10000, unit: .feet),
          surfaceType: .grooved,
          thresholdCoordinate: CLLocationCoordinate2D(
            latitude: 37.70169270833333,
            longitude: -122.21455729166667
          ),
          thresholdCrossingHeight: .init(value: 71, unit: .feet),
          glidepathAngle: .init(value: 3.0, unit: .degrees),
          displacedThresholdDistance: .init(value: 114, unit: .feet),
          airport: airport
        ),
        .init(
          name: "10R",
          elevation: .init(value: 8.9, unit: .feet),
          trueHeading: .init(value: 112, unit: .degrees),
          gradient: nil,
          length: .init(value: 6213, unit: .feet),
          width: .init(value: 150, unit: .feet),
          takeoffRun: .init(value: 6213, unit: .feet),
          takeoffDistance: .init(value: 6213, unit: .feet),
          landingDistance: .init(value: 6213, unit: .feet),
          surfaceType: .grooved,
          thresholdCoordinate: CLLocationCoordinate2D(
            latitude: 37.72870659722222,
            longitude: -122.22590277777778
          ),
          thresholdCrossingHeight: .init(value: 50, unit: .feet),
          glidepathAngle: .init(value: 3.0, unit: .degrees),
          airport: airport
        ),
        .init(
          name: "28L",
          elevation: .init(value: 8.6, unit: .feet),
          trueHeading: .init(value: 292, unit: .degrees),
          gradient: nil,
          length: .init(value: 6213, unit: .feet),
          width: .init(value: 150, unit: .feet),
          takeoffRun: .init(value: 6213, unit: .feet),
          takeoffDistance: .init(value: 6213, unit: .feet),
          landingDistance: .init(value: 6213, unit: .feet),
          surfaceType: .grooved,
          thresholdCoordinate: CLLocationCoordinate2D(
            latitude: 37.72227430555556,
            longitude: -122.20600694444444
          ),
          thresholdCrossingHeight: .init(value: 50, unit: .feet),
          glidepathAngle: .init(value: 3.0, unit: .degrees),
          airport: airport
        ),
        .init(
          name: "10L",
          elevation: .init(value: 6.3, unit: .feet),
          trueHeading: .init(value: 112, unit: .degrees),
          gradient: nil,
          length: .init(value: 5457, unit: .feet),
          width: .init(value: 150, unit: .feet),
          takeoffRun: .init(value: 5457, unit: .feet),
          takeoffDistance: .init(value: 5457, unit: .feet),
          landingDistance: .init(value: 5336, unit: .feet),
          surfaceType: .grooved,
          thresholdCoordinate: CLLocationCoordinate2D(
            latitude: 37.73046875,
            longitude: -122.22217881944445
          ),
          thresholdCrossingHeight: .init(value: 50, unit: .feet),
          glidepathAngle: .init(value: 3.0, unit: .degrees),
          airport: airport
        ),
        // ILS RWY 28R: TCH 51 ft, 3° glideslope
        .init(
          name: "28R",
          elevation: .init(value: 6.8, unit: .feet),
          trueHeading: .init(value: 292, unit: .degrees),
          gradient: nil,
          length: .init(value: 5457, unit: .feet),
          width: .init(value: 150, unit: .feet),
          takeoffRun: .init(value: 5457, unit: .feet),
          takeoffDistance: .init(value: 5457, unit: .feet),
          landingDistance: .init(value: 5457, unit: .feet),
          surfaceType: .grooved,
          thresholdCoordinate: CLLocationCoordinate2D(
            latitude: 37.72481336805556,
            longitude: -122.20470486111111
          ),
          thresholdCrossingHeight: .init(value: 51, unit: .feet),
          glidepathAngle: .init(value: 3.0, unit: .degrees),
          airport: airport
        ),
        .init(
          name: "15",
          elevation: .init(value: 4.6, unit: .feet),
          trueHeading: .init(value: 164, unit: .degrees),
          gradient: nil,
          length: .init(value: 3376, unit: .feet),
          width: .init(value: 75, unit: .feet),
          takeoffRun: nil,
          takeoffDistance: nil,
          landingDistance: nil,
          surfaceType: .paved,
          thresholdCoordinate: CLLocationCoordinate2D(
            latitude: 37.74029079861111,
            longitude: -122.2228125
          ),
          airport: airport
        ),
        .init(
          name: "33",
          elevation: .init(value: 4.6, unit: .feet),
          trueHeading: .init(value: 344, unit: .degrees),
          gradient: nil,
          length: .init(value: 3376, unit: .feet),
          width: .init(value: 75, unit: .feet),
          takeoffRun: nil,
          takeoffDistance: nil,
          landingDistance: nil,
          surfaceType: .paved,
          thresholdCoordinate: CLLocationCoordinate2D(
            latitude: 37.73136284722222,
            longitude: -122.21967013888889
          ),
          airport: airport
        )
      ]
    }
  )
}
