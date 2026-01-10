import CoreLocation
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
        .init(
          name: "12",
          elevation: .init(value: 8.3, unit: .feet),
          trueHeading: .init(value: 130, unit: .degrees),
          gradient: nil,
          length: .init(value: 10520, unit: .feet),
          width: .init(value: 150, unit: .feet),
          takeoffRun: .init(value: 10000, unit: .feet),
          takeoffDistance: .init(value: 10000, unit: .feet),
          landingDistance: .init(value: 10000, unit: .feet),
          isTurf: false,
          thresholdCoordinate: CLLocationCoordinate2D(
            latitude: 37.72006076388889,
            longitude: -122.2421180555556
          ),
          airport: airport
        ),
        .init(
          name: "30",
          elevation: .init(value: 9, unit: .feet),
          trueHeading: .init(value: 310, unit: .degrees),
          gradient: nil,
          length: .init(value: 10520, unit: .feet),
          width: .init(value: 150, unit: .feet),
          takeoffRun: .init(value: 10000, unit: .feet),
          takeoffDistance: .init(value: 10520, unit: .feet),
          landingDistance: .init(value: 10000, unit: .feet),
          isTurf: false,
          thresholdCoordinate: CLLocationCoordinate2D(
            latitude: 37.70149305555555,
            longitude: -122.2142621527778
          ),
          airport: airport
        ),
        .init(
          name: "10R",
          elevation: .init(value: 8, unit: .feet),
          trueHeading: .init(value: 112, unit: .degrees),
          gradient: nil,
          length: .init(value: 6213, unit: .feet),
          width: .init(value: 150, unit: .feet),
          takeoffRun: .init(value: 6213, unit: .feet),
          takeoffDistance: .init(value: 6213, unit: .feet),
          landingDistance: .init(value: 6213, unit: .feet),
          isTurf: false,
          thresholdCoordinate: CLLocationCoordinate2D(
            latitude: 37.72870659722222,
            longitude: -122.2259027777778
          ),
          airport: airport
        ),
        .init(
          name: "28L",
          elevation: .init(value: 8.2, unit: .feet),
          trueHeading: .init(value: 292, unit: .degrees),
          gradient: nil,
          length: .init(value: 6213, unit: .feet),
          width: .init(value: 150, unit: .feet),
          takeoffRun: .init(value: 6213, unit: .feet),
          takeoffDistance: .init(value: 6213, unit: .feet),
          landingDistance: .init(value: 6213, unit: .feet),
          isTurf: false,
          thresholdCoordinate: CLLocationCoordinate2D(
            latitude: 37.72227430555556,
            longitude: -122.2060069444444
          ),
          airport: airport
        ),
        .init(
          name: "10L",
          elevation: .init(value: 5.5, unit: .feet),
          trueHeading: .init(value: 112, unit: .degrees),
          gradient: nil,
          length: .init(value: 5457, unit: .feet),
          width: .init(value: 150, unit: .feet),
          takeoffRun: .init(value: 5457, unit: .feet),
          takeoffDistance: .init(value: 5457, unit: .feet),
          landingDistance: .init(value: 5336, unit: .feet),
          isTurf: false,
          thresholdCoordinate: CLLocationCoordinate2D(
            latitude: 37.73046875,
            longitude: -122.2221788194445
          ),
          airport: airport
        ),
        .init(
          name: "28R",
          elevation: .init(value: 5.8, unit: .feet),
          trueHeading: .init(value: 292, unit: .degrees),
          gradient: nil,
          length: .init(value: 5457, unit: .feet),
          width: .init(value: 150, unit: .feet),
          takeoffRun: .init(value: 5457, unit: .feet),
          takeoffDistance: .init(value: 5457, unit: .feet),
          landingDistance: .init(value: 5457, unit: .feet),
          isTurf: false,
          thresholdCoordinate: CLLocationCoordinate2D(
            latitude: 37.72481336805556,
            longitude: -122.2047048611111
          ),
          airport: airport
        ),
        .init(
          name: "15",
          elevation: .init(value: 1.4, unit: .feet),
          trueHeading: .init(value: 164, unit: .degrees),
          gradient: nil,
          length: .init(value: 3376, unit: .feet),
          width: .init(value: 75, unit: .feet),
          takeoffRun: nil,
          takeoffDistance: nil,
          landingDistance: nil,
          isTurf: false,
          airport: airport
        ),
        .init(
          name: "33",
          elevation: .init(value: 3.9, unit: .feet),
          trueHeading: .init(value: 344, unit: .degrees),
          gradient: nil,
          length: .init(value: 3376, unit: .feet),
          width: .init(value: 75, unit: .feet),
          takeoffRun: nil,
          takeoffDistance: nil,
          landingDistance: nil,
          isTurf: false,
          airport: airport
        )
      ]
    }
  )
}
