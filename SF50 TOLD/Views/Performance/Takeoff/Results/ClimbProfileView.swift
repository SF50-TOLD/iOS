import Combine
import Defaults
import SF50_Shared
import SwiftData
import SwiftUI

struct ClimbProfileView: View {

  // MARK: - Constants

  private static let chartHeightPts: CGFloat = 300
  private static let vectorTargetAltitudeFtAFE: Double = 2000
  private static let maxWindsAltitudeFt: Double = 18000
  private static let windsAltitudeStepFt: Double = 3000
  private static let obstacleCeilingFtAFE: Double = 600

  @Environment(TakeoffPerformanceViewModel.self)
  private var performance

  @Environment(WeatherViewModel.self)
  private var weather

  @Environment(\.modelContext)
  private var modelContext

  @Environment(\.aircraftType)
  private var aircraftType

  @Default(.useRegressionModel)
  private var useRegressionModel

  // MARK: - Climb configuration

  @State private var firstSegment: FirstSegment = .takeoff2min
  @State private var firstSegmentAntiIce = false
  @State private var secondSegment: SecondSegment = .enrouteObstacle
  @State private var secondSegmentAntiIce = false

  // MARK: - Departure configuration

  @State private var departureType: DepartureType = .runwayHeading
  @State private var vectorHeading = Measurement(value: 0, unit: UnitAngle.degrees)
  @State private var vectorTrack = Measurement(value: 0, unit: UnitAngle.degrees)
  @State private var selectedDepartureID: String?

  // MARK: - Output

  @State private var terrainPath: ProcedureTerrainPath?
  @State private var isComputing = false
  @State private var pathFailed = false
  @State private var terrainRevision = 0

  var body: some View {
    List {
      climbProfileSection
      departureSection
      chartSection
    }
    .navigationTitle("Climb Profile")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        if let terrainPath {
          TerrainDataStatusButton(
            terrainDataAvailable: terrainPath.terrainDataAvailable,
            terrainDataCorrupted: !TerrainDataLoader.shared.corruptedRegions.isEmpty,
            obstacleDataAvailable: terrainPath.obstacleDataAvailable
          )
        }
      }
    }
    .task(id: computationInputs) {
      await computeTerrainPath()
    }
    .onReceive(NotificationCenter.default.publisher(for: .terrainRegionsDidChange)) { _ in
      terrainRevision += 1
    }
    .onChange(of: hasPlottableDepartures) { _, hasPlottable in
      if !hasPlottable && departureType == .procedure {
        departureType = .runwayHeading
      }
    }
    .onChange(of: availableDepartures.map(\.identifier), initial: true) { _, newIDs in
      if let selectedDepartureID, newIDs.contains(selectedDepartureID) { return }
      selectedDepartureID =
        availableDepartures.first {
          $0.isPlottable(forRunway: performance.runway?.name ?? "")
        }?.identifier
    }
    .onChange(of: performance.runway?.name, initial: true) { _, _ in
      if let heading = performance.runway?.magneticHeading {
        vectorHeading = heading
        vectorTrack = heading
      }
    }
  }

  // MARK: - Sections

  private var climbProfileSection: some View {
    Section("Climb Profile") {
      Picker("First Segment", selection: $firstSegment) {
        ForEach(FirstSegment.allCases) { segment in
          Text(segment.label).tag(segment)
        }
      }
      if firstSegment.showsAntiIce {
        Toggle("Anti-Ice", isOn: $firstSegmentAntiIce)
      }
      if firstSegment.showsSecondSegment {
        Picker("Second Segment", selection: $secondSegment) {
          ForEach(SecondSegment.allCases) { segment in
            Text(segment.label).tag(segment)
          }
        }
        if secondSegment.showsAntiIce {
          Toggle("Anti-Ice", isOn: $secondSegmentAntiIce)
        }
      }
    }
  }

  private var departureSection: some View {
    Section("Departure") {
      Picker("Type", selection: $departureType) {
        ForEach(availableDepartureTypes) { type in
          Text(type.label).tag(type)
        }
      }
      switch departureType {
        case .runwayHeading:
          EmptyView()
        case .vectorHeading:
          MeasurementField(
            "Heading",
            value: $vectorHeading,
            format: .heading
          )
        case .vectorTrack:
          MeasurementField(
            "Track",
            value: $vectorTrack,
            format: .heading
          )
        case .procedure:
          Picker("SID", selection: $selectedDepartureID) {
            ForEach(availableDepartures, id: \.identifier) { departure in
              Text(departure.identifier)
                .tag(Optional(departure.identifier))
                .selectionDisabled(
                  !departure.isPlottable(forRunway: performance.runway?.name ?? "")
                )
            }
          }
      }
    }
  }

  @ViewBuilder private var chartSection: some View {
    Section("Terrain Profile") {
      if isComputing {
        HStack {
          Spacer()
          TerrainComputingIndicator()
          Spacer()
        }
        .padding()
      } else if let terrainPath {
        let fieldElevation = performance.airport?.elevation.converted(to: .feet).value ?? 0
        TerrainProfileChartView(
          terrainPath: terrainPath,
          fieldElevationFt: fieldElevation
        )
        .frame(height: Self.chartHeightPts)
      } else if pathFailed {
        ContentUnavailableView(
          "Unable to Plot",
          systemImage: "mountain.2",
          description: Text("The path for this procedure could not be computed.")
        )
      } else {
        ContentUnavailableView(
          "No Data",
          systemImage: "mountain.2",
          description: Text("Select a departure procedure to view terrain profile.")
        )
      }
    }
  }

  // MARK: - Computed Properties

  private var availableDepartures: [Procedure] {
    guard let airport = performance.airport,
      let runwayName = performance.runway?.name
    else { return [] }
    return airport.departureProcedures
      .filter { $0.runwayNames.isEmpty || $0.runwayNames.contains(runwayName) }
      .sorted { $0.identifier < $1.identifier }
  }

  private var hasPlottableDepartures: Bool {
    availableDepartures.contains { $0.isPlottable(forRunway: performance.runway?.name ?? "") }
  }

  private var availableDepartureTypes: [DepartureType] {
    DepartureType.allCases.filter { $0 != .procedure || hasPlottableDepartures }
  }

  private var selectedDeparture: Procedure? {
    guard let id = selectedDepartureID else { return nil }
    return availableDepartures.first { $0.identifier == id }
  }

  private var computationInputs: ComputationInputs? {
    guard let runway = performance.runway,
      let airport = performance.airport
    else { return nil }

    // For procedure departures, require a plottable SID
    if departureType == .procedure {
      guard let departure = selectedDeparture, departure.isPlottable(forRunway: runway.name) else {
        return nil
      }
    }

    let windsHash: Int
    if case .value(let data) = weather.windsAloft, let data {
      windsHash = data.entries.count
    } else {
      windsHash = 0
    }

    return ComputationInputs(
      runwayName: runway.name,
      weightLb: performance.weight.converted(to: .pounds).value,
      slpInHg: performance.conditions.seaLevelPressure?
        .converted(to: .inchesOfMercury).value
        ?? standardSeaLevelPressure.converted(to: .inchesOfMercury).value,
      aircraftType: aircraftType,
      useRegressionModel: useRegressionModel,
      firstSegment: firstSegment,
      firstSegmentAntiIce: firstSegmentAntiIce,
      secondSegment: secondSegment,
      secondSegmentAntiIce: secondSegmentAntiIce,
      departureType: departureType,
      departureID: selectedDeparture?.identifier,
      vectorHeadingDeg: vectorHeading.converted(to: .degrees).value,
      vectorTrackDeg: vectorTrack.converted(to: .degrees).value,
      airportID: airport.recordID,
      windsHash: windsHash,
      terrainRevision: terrainRevision
    )
  }

  // MARK: - Computation

  private func computeTerrainPath() async {
    guard let airport = performance.airport,
      let runway = performance.runway,
      let takeoffPoint = runway.takeoffStartCoordinate
    else {
      terrainPath = nil
      pathFailed = false
      return
    }

    isComputing = true
    defer { isComputing = false }

    let windsAloftObs = buildWindsAloftObservations()
    let fieldElevationFt = airport.elevation.converted(to: .feet).value

    let slpInHg =
      performance.conditions.seaLevelPressure?
      .converted(to: .inchesOfMercury).value
      ?? standardSeaLevelPressure.converted(to: .inchesOfMercury).value

    let climbProfile = ClimbProfileGenerator.generate(
      windsAloft: windsAloftObs,
      weightLb: performance.weight.converted(to: .pounds).value,
      aircraftType: aircraftType,
      seaLevelPressureInHg: slpInHg,
      useRegressionModel: useRegressionModel
    )

    let schedule = buildClimbSchedule()
    let pathGenerator = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: schedule,
      magneticVariation: airport.variation
    )

    let procedurePath: ProcedurePath?
    switch departureType {
      case .procedure:
        guard let departure = selectedDeparture, departure.isPlottable(forRunway: runway.name)
        else {
          terrainPath = nil
          return
        }
        let legs = departure.composedLegs(forRunway: runway.name)
        procedurePath = pathGenerator.departurePath(
          from: legs,
          takeoffPoint: takeoffPoint,
          takeoffPointAltitudeFt: fieldElevationFt
        )
      case .runwayHeading:
        procedurePath = pathGenerator.headingPath(
          from: takeoffPoint,
          magneticDirection: runway.magneticHeading,
          isHeading: true,
          startAltitudeFt: fieldElevationFt,
          targetAltitudeFt: fieldElevationFt + Self.vectorTargetAltitudeFtAFE
        )
      case .vectorHeading:
        procedurePath = pathGenerator.headingPath(
          from: takeoffPoint,
          magneticDirection: vectorHeading,
          isHeading: true,
          startAltitudeFt: fieldElevationFt,
          targetAltitudeFt: fieldElevationFt + Self.vectorTargetAltitudeFtAFE
        )
      case .vectorTrack:
        procedurePath = pathGenerator.headingPath(
          from: takeoffPoint,
          magneticDirection: vectorTrack,
          isHeading: false,
          startAltitudeFt: fieldElevationFt,
          targetAltitudeFt: fieldElevationFt + Self.vectorTargetAltitudeFtAFE
        )
    }

    guard let procedurePath else {
      terrainPath = nil
      pathFailed = true
      return
    }

    guard !Task.isCancelled else { return }

    let terrainGenerator = ProcedureTerrainPathGenerator(
      modelContainer: modelContext.container
    )
    let result = await terrainGenerator.generate(from: procedurePath)

    guard !Task.isCancelled else { return }
    terrainPath = result
    pathFailed = false
  }

  private func buildWindsAloftObservations() -> [ClimbProfileGenerator.WindsAloftObservation] {
    guard case .value(let data) = weather.windsAloft, let data else {
      return defaultWindsAloftObservations()
    }
    return data.entries.map { entry in
      ClimbProfileGenerator.WindsAloftObservation(
        altitudeFt: entry.altitude.converted(to: .feet).value,
        temperatureC: entry.temperature?.converted(to: .celsius).value
          ?? isaTemperature(altitudeFt: entry.altitude.converted(to: .feet).value),
        windDirectionDeg: entry.windDirection?.converted(to: .degrees).value ?? 0,
        windSpeedKts: entry.windSpeed.converted(to: .knots).value
      )
    }
  }

  private func defaultWindsAloftObservations() -> [ClimbProfileGenerator.WindsAloftObservation] {
    let temp =
      performance.conditions.temperature?.converted(to: .celsius).value
      ?? seaLevelStandardTempC
    let fieldElevationFt = performance.airport?.elevation.converted(to: .feet).value ?? 0
    return stride(
      from: fieldElevationFt,
      through: Self.maxWindsAltitudeFt,
      by: Self.windsAltitudeStepFt
    ).map { alt in
      ClimbProfileGenerator.WindsAloftObservation(
        altitudeFt: alt,
        temperatureC: alt == fieldElevationFt ? temp : isaTemperature(altitudeFt: alt),
        windDirectionDeg: performance.conditions.windDirection?.converted(to: .degrees).value ?? 0,
        windSpeedKts: performance.conditions.windSpeed?.converted(to: .knots).value ?? 0
      )
    }
  }

  private func buildClimbSchedule() -> ProcedurePathGenerator.ClimbSchedule {
    let fieldElevationFt = performance.airport?.elevation.converted(to: .feet).value ?? 0
    let takeoffCeilingFt = fieldElevationFt + ProcedurePathGenerator.screenHeightFt
    let obstacleCeilingFt = fieldElevationFt + Self.obstacleCeilingFtAFE

    typealias Segment = ProcedurePathGenerator.ClimbSegment

    var segments: [Segment]

    switch firstSegment {
      case .enroute:
        // [takeoff until 35'AFE, enrouteObstacle until 600'AFE, enroute]
        let antiIce = firstSegmentAntiIce
        segments = [
          Segment(
            profile: .takeoff,
            upperBound: .altitude(.init(value: takeoffCeilingFt, unit: .feet))
          ),
          Segment(
            profile: .enrouteObstacle(antiIce: antiIce),
            upperBound: .altitude(.init(value: obstacleCeilingFt, unit: .feet))
          ),
          Segment(profile: .enroute(antiIce: antiIce))
        ]
      case .enrouteObstacle:
        // [takeoff until 35'AFE, enrouteObstacle]
        let antiIce = firstSegmentAntiIce
        segments = [
          Segment(
            profile: .takeoff,
            upperBound: .altitude(.init(value: takeoffCeilingFt, unit: .feet))
          ),
          Segment(profile: .enrouteObstacle(antiIce: antiIce))
        ]
      case .takeoff2min:
        let second = secondSegment.profileType(antiIce: secondSegmentAntiIce)
        // [takeoff until 2min, ...]
        segments = [
          Segment(profile: .takeoff, upperBound: .time(.init(value: 2, unit: .minutes)))
        ]
        if case .enroute = secondSegment {
          // [takeoff until 2min, enrouteObstacle until 600'AFE, enroute]
          segments.append(
            Segment(
              profile: .enrouteObstacle(antiIce: secondSegmentAntiIce),
              upperBound: .altitude(.init(value: obstacleCeilingFt, unit: .feet))
            )
          )
        }
        segments.append(Segment(profile: second))
      case .takeoff5min:
        let second = secondSegment.profileType(antiIce: secondSegmentAntiIce)
        // [takeoff until 5min, second]
        segments = [
          Segment(profile: .takeoff, upperBound: .time(.init(value: 5, unit: .minutes))),
          Segment(profile: second)
        ]
    }

    return ProcedurePathGenerator.ClimbSchedule(segments: segments)
  }

  // MARK: - Types

  private struct ComputationInputs: Equatable {
    let runwayName: String
    let weightLb: Double
    let slpInHg: Double
    let aircraftType: AircraftType
    let useRegressionModel: Bool
    let firstSegment: FirstSegment
    let firstSegmentAntiIce: Bool
    let secondSegment: SecondSegment
    let secondSegmentAntiIce: Bool
    let departureType: DepartureType
    let departureID: String?
    let vectorHeadingDeg: Double
    let vectorTrackDeg: Double
    let airportID: String
    let windsHash: Int
    let terrainRevision: Int
  }

  enum FirstSegment: String, CaseIterable, Identifiable {
    case takeoff2min, takeoff5min, enrouteObstacle, enroute

    var id: String { rawValue }

    var label: String {
      switch self {
        case .takeoff2min: "Takeoff (2 min)"
        case .takeoff5min: "Takeoff (5 min)"
        case .enrouteObstacle: "Enroute Obstacle"
        case .enroute: "Enroute"
      }
    }

    var showsAntiIce: Bool {
      self == .enrouteObstacle || self == .enroute
    }

    var showsSecondSegment: Bool {
      self == .takeoff2min || self == .takeoff5min
    }
  }

  enum SecondSegment: String, CaseIterable, Identifiable {
    case enrouteObstacle, enroute

    var id: String { rawValue }

    var label: String {
      switch self {
        case .enrouteObstacle: "Enroute Obstacle"
        case .enroute: "Enroute"
      }
    }

    var showsAntiIce: Bool { true }

    func profileType(antiIce: Bool) -> ClimbProfile.ProfileType {
      switch self {
        case .enrouteObstacle: .enrouteObstacle(antiIce: antiIce)
        case .enroute: .enroute(antiIce: antiIce)
      }
    }
  }

  enum DepartureType: String, CaseIterable, Identifiable {
    case runwayHeading, vectorHeading, vectorTrack, procedure

    var id: String { rawValue }

    var label: String {
      switch self {
        case .runwayHeading: "Runway Heading"
        case .vectorHeading: "Vector (Heading)"
        case .vectorTrack: "Vector (Track)"
        case .procedure: "Procedure"
      }
    }
  }
}

#Preview {
  PreviewView(insert: .KOAK) { helper in
    let runway = try helper.load(airportID: "OAK", runway: "28L")!
    helper.setTakeoff(runway: runway)

    return NavigationStack {
      ClimbProfileView()
    }
    .environment(TakeoffPerformanceViewModel(container: helper.container))
    .environment(WeatherViewModel(operation: .takeoff, container: helper.container))
  }
}
