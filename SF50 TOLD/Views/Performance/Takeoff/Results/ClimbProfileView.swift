import Combine
import Defaults
import SF50_Shared
import SwiftData
import SwiftUI

struct ClimbProfileView: View {

  // MARK: - Constants

  private static let vectorTargetAltitudeAFE = Measurement(value: 2000, unit: UnitLength.feet),
    obstacleCeilingAFE = Measurement(value: 600, unit: UnitLength.feet)

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
  @State private var climbProfile: ClimbProfile?
  @State private var isComputing = false
  @State private var pathFailed = false
  @State private var terrainRevision = 0

  var body: some View {
    List {
      ClimbConfigurationSection(
        firstSegment: $firstSegment,
        firstSegmentAntiIce: $firstSegmentAntiIce,
        secondSegment: $secondSegment,
        secondSegmentAntiIce: $secondSegmentAntiIce
      )
      DepartureSection(
        departureType: $departureType,
        vectorHeading: $vectorHeading,
        vectorTrack: $vectorTrack,
        selectedDepartureID: $selectedDepartureID,
        availableTypes: availableDepartureTypes,
        availableDepartures: availableDepartures,
        runwayName: performance.runway?.name ?? ""
      )
      TerrainProfileSection(
        terrainPath: terrainPath,
        climbProfile: climbProfile,
        hasWindsAloft: windsAloft != nil,
        fieldElevation: performance.airport?.elevation ?? .zero,
        time: weather.time,
        isComputing: isComputing,
        pathFailed: pathFailed,
        noDataDescription: "Select a departure procedure to view terrain profile."
      )
    }
    .navigationTitle("Climb Profile")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        if let terrainPath {
          DataStatusButton(
            terrainDataAvailable: terrainPath.terrainDataAvailable,
            terrainDataCorrupted: !TerrainDataLoader.shared.corruptedRegions.isEmpty,
            obstacleDataAvailable: terrainPath.obstacleDataAvailable,
            windsAloft: weather.windsAloft,
            timeZone: displayTimeZone
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

  private var windsAloft: WindsAloftForecast? {
    guard case .value(let forecast) = weather.windsAloft else { return nil }
    return forecast
  }

  private var displayTimeZone: TimeZone {
    .display(for: performance.airport)
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

    return ComputationInputs(
      runwayName: runway.name,
      weightLb: performance.weight.converted(to: .pounds).value,
      slpInHg: performance.conditions.seaLevelPressure?
        .converted(to: .inchesOfMercury).value
        ?? standardSeaLevelPressure.converted(to: .inchesOfMercury).value,
      surfaceTemperatureC: performance.conditions.temperature?.converted(to: .celsius).value,
      conditionsSource: performance.conditions.source,
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
      windsAloft: windsAloft,
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
      climbProfile = nil
      pathFailed = false
      return
    }

    isComputing = true
    defer { isComputing = false }

    let windsAloftObs = ClimbProfileGenerator.windsAloftObservations(
      for: windsAloft,
      conditions: performance.conditions,
      fieldElevation: airport.elevation
    )
    let fieldElevation = airport.elevation,
      fieldElevationFt = fieldElevation.converted(to: .feet).value,
      targetAltitudeFt = (fieldElevation + Self.vectorTargetAltitudeAFE)
        .converted(to: .feet).value

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
    self.climbProfile = climbProfile

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
          targetAltitudeFt: targetAltitudeFt
        )
      case .vectorHeading:
        procedurePath = pathGenerator.headingPath(
          from: takeoffPoint,
          magneticDirection: vectorHeading,
          isHeading: true,
          startAltitudeFt: fieldElevationFt,
          targetAltitudeFt: targetAltitudeFt
        )
      case .vectorTrack:
        procedurePath = pathGenerator.headingPath(
          from: takeoffPoint,
          magneticDirection: vectorTrack,
          isHeading: false,
          startAltitudeFt: fieldElevationFt,
          targetAltitudeFt: targetAltitudeFt
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

  private func buildClimbSchedule() -> ProcedurePathGenerator.ClimbSchedule {
    let fieldElevation = performance.airport?.elevation ?? .zero
    let takeoffCeiling = fieldElevation + ProcedurePathGenerator.screenHeight,
      obstacleCeiling = fieldElevation + Self.obstacleCeilingAFE

    typealias Segment = ProcedurePathGenerator.ClimbSegment

    var segments: [Segment]

    switch firstSegment {
      case .enroute:
        // [takeoff until 35'AFE, enrouteObstacle until 600'AFE, enroute]
        let antiIce = firstSegmentAntiIce
        segments = [
          Segment(
            profile: .takeoff,
            upperBound: .altitude(takeoffCeiling)
          ),
          Segment(
            profile: .enrouteObstacle(antiIce: antiIce),
            upperBound: .altitude(obstacleCeiling)
          ),
          Segment(profile: .enroute(antiIce: antiIce))
        ]
      case .enrouteObstacle:
        // [takeoff until 35'AFE, enrouteObstacle]
        let antiIce = firstSegmentAntiIce
        segments = [
          Segment(
            profile: .takeoff,
            upperBound: .altitude(takeoffCeiling)
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
              upperBound: .altitude(obstacleCeiling)
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

    /// The temperature at the field.
    ///
    /// Only the calm column synthesized when no forecast covers the flight is built from it — but
    /// that is the column a profile planned in the air, on entered weather, is flown on, so a
    /// changed temperature has to reach the path.
    let surfaceTemperatureC: Double?

    /// Where that temperature came from.
    ///
    /// Entered weather is carried up the synthesized column and downloaded weather is not, so the
    /// same reading gives a different climb depending on who said it.
    let conditionsSource: Conditions.Source
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
    let windsAloft: WindsAloftForecast?
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

/// The climb schedule the profile is flown on.
private struct ClimbConfigurationSection: View {

  @Binding var firstSegment: ClimbProfileView.FirstSegment
  @Binding var firstSegmentAntiIce: Bool
  @Binding var secondSegment: ClimbProfileView.SecondSegment
  @Binding var secondSegmentAntiIce: Bool

  var body: some View {
    Section("Climb Profile") {
      Picker("First Segment", selection: $firstSegment) {
        ForEach(ClimbProfileView.FirstSegment.allCases) { segment in
          Text(segment.label).tag(segment)
        }
      }
      if firstSegment.showsAntiIce {
        Toggle("Anti-Ice", isOn: $firstSegmentAntiIce)
      }
      if firstSegment.showsSecondSegment {
        Picker("Second Segment", selection: $secondSegment) {
          ForEach(ClimbProfileView.SecondSegment.allCases) { segment in
            Text(segment.label).tag(segment)
          }
        }
        if secondSegment.showsAntiIce {
          Toggle("Anti-Ice", isOn: $secondSegmentAntiIce)
        }
      }
    }
  }
}

/// How the aircraft leaves the runway, and the fields each way of leaving needs.
private struct DepartureSection: View {

  @Binding var departureType: ClimbProfileView.DepartureType
  @Binding var vectorHeading: Measurement<UnitAngle>
  @Binding var vectorTrack: Measurement<UnitAngle>
  @Binding var selectedDepartureID: String?

  let availableTypes: [ClimbProfileView.DepartureType]
  let availableDepartures: [Procedure]

  /// The runway being departed, which decides which procedures can be plotted.
  let runwayName: String

  var body: some View {
    Section("Departure") {
      Picker("Type", selection: $departureType) {
        ForEach(availableTypes) { type in
          Text(type.label).tag(type)
        }
      }
      .accessibilityIdentifier("departureTypePicker")
      switch departureType {
        case .runwayHeading:
          EmptyView()
        case .vectorHeading:
          MeasurementField("Heading", value: $vectorHeading, format: .heading)
        case .vectorTrack:
          MeasurementField("Track", value: $vectorTrack, format: .heading)
        case .procedure:
          Picker("SID", selection: $selectedDepartureID) {
            ForEach(availableDepartures, id: \.identifier) { departure in
              Text(departure.identifier)
                .tag(Optional(departure.identifier))
                .selectionDisabled(!departure.isPlottable(forRunway: runwayName))
            }
          }
          .accessibilityIdentifier("departureProcedurePicker")
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
    .environment(\.pathAtmosphereLoader, PreviewPathAtmosphereLoader(.loaded(.preview)))
  }
}
