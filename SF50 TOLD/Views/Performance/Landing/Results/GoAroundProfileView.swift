import Combine
import Defaults
import SF50_Shared
import SwiftData
import SwiftUI

struct GoAroundProfileView: View {

  // MARK: - Constants

  private static let chartHeightPts: CGFloat = 300
  private static let vectorTargetAltitudeFtAFE: Double = 2000
  private static let maxWindsAltitudeFt: Double = 18000
  private static let windsAltitudeStepFt: Double = 3000

  @Environment(LandingPerformanceViewModel.self)
  private var performance

  @Environment(WeatherViewModel.self)
  private var weather

  @Environment(\.modelContext)
  private var modelContext

  @Environment(\.aircraftType)
  private var aircraftType

  @Default(.useRegressionModel)
  private var useRegressionModel

  // MARK: - Go-around configuration

  @State private var goAroundType: GoAroundType = .publishedMissed
  @State private var vectorHeading = Measurement(value: 0, unit: UnitAngle.degrees)
  @State private var selectedApproachID: String?

  // MARK: - Output

  @State private var terrainPath: ProcedureTerrainPath?
  @State private var isComputing = false
  @State private var pathFailed = false
  @State private var terrainRevision = 0

  var body: some View {
    List {
      goAroundSection
      chartSection
    }
    .navigationTitle("Go-Around Profile")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        if let terrainPath {
          TerrainDataStatusButton(
            terrainDataAvailable: terrainPath.terrainDataAvailable,
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
    .onChange(of: hasPlottableApproaches) { _, hasPlottable in
      if !hasPlottable && goAroundType == .publishedMissed {
        goAroundType = .vectors
      }
    }
    .onChange(of: availableApproaches.map(\.identifier), initial: true) { _, newIDs in
      if let selectedApproachID, newIDs.contains(selectedApproachID) { return }
      selectedApproachID = preferredPlottableApproach?.identifier
    }
    .onChange(of: performance.runway?.name, initial: true) { _, _ in
      if let heading = performance.runway?.magneticHeading {
        vectorHeading = heading
      }
    }
  }

  // MARK: - Sections

  private var goAroundSection: some View {
    Section("Go-Around Procedure") {
      Picker("Type", selection: $goAroundType) {
        ForEach(availableGoAroundTypes) { type in
          Text(type.label).tag(type)
        }
      }
      switch goAroundType {
        case .publishedMissed:
          Picker("Approach", selection: $selectedApproachID) {
            ForEach(availableApproaches, id: \.identifier) { approach in
              Text(approach.name ?? approach.identifier)
                .tag(Optional(approach.identifier))
                .selectionDisabled(
                  !approach.isMissedApproachPlottable
                )
            }
          }
        case .vectors:
          MeasurementField(
            "Heading",
            value: $vectorHeading,
            format: .heading
          )
      }
    }
  }

  @ViewBuilder private var chartSection: some View {
    Section {
      if isComputing {
        HStack {
          Spacer()
          ProgressView("Computing terrain path…")
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
          description: Text("Select an approach to view missed approach terrain profile.")
        )
      }
    }
  }

  // MARK: - Computed Properties

  private var availableApproaches: [Procedure] {
    guard let airport = performance.airport,
      let runwayName = performance.runway?.name
    else { return [] }
    return airport.approachProcedures
      .filter { $0.runwayName == nil || $0.runwayName == runwayName }
      .sorted { ($0.name ?? $0.identifier) < ($1.name ?? $1.identifier) }
  }

  private var hasPlottableApproaches: Bool {
    availableApproaches.contains(where: \.isMissedApproachPlottable)
  }

  /// Selects the best default approach: prefer runway-specific over circling.
  private var preferredPlottableApproach: Procedure? {
    let plottable = availableApproaches.filter(\.isMissedApproachPlottable)
    let runwayName = performance.runway?.name ?? ""
    return plottable.first { $0.runwayName != nil }
      ?? plottable.first { !runwayName.isEmpty && ($0.name ?? "").contains(runwayName) }
      ?? plottable.first
  }

  private var availableGoAroundTypes: [GoAroundType] {
    GoAroundType.allCases.filter { $0 != .publishedMissed || hasPlottableApproaches }
  }

  private var selectedApproach: Procedure? {
    guard let id = selectedApproachID else { return nil }
    return availableApproaches.first { $0.identifier == id }
  }

  private var computationInputs: ComputationInputs? {
    guard let runway = performance.runway,
      let airport = performance.airport
    else { return nil }

    // For published missed, require a plottable approach
    if goAroundType == .publishedMissed {
      guard let approach = selectedApproach, approach.isMissedApproachPlottable else { return nil }
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
      goAroundType: goAroundType,
      approachID: selectedApproach?.identifier,
      vectorHeadingDeg: vectorHeading.converted(to: .degrees).value,
      airportID: airport.recordID,
      windsHash: windsHash,
      terrainRevision: terrainRevision
    )
  }

  // MARK: - Computation

  private func computeTerrainPath() async {
    guard let airport = performance.airport,
      let runway = performance.runway,
      let thresholdCoord = runway.thresholdCoordinate
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

    // Fixed schedule for go-around: TO 2min → Enroute Obstacle
    let schedule = ProcedurePathGenerator.ClimbSchedule(segments: [
      .init(profile: .takeoff, upperBound: .time(.init(value: 2, unit: .minutes))),
      .init(profile: .enrouteObstacle(antiIce: false))
    ])

    let pathGenerator = ProcedurePathGenerator(
      climbProfile: climbProfile,
      schedule: schedule,
      magneticVariation: airport.variation
    )

    let procedurePath: ProcedurePath?
    switch goAroundType {
      case .publishedMissed:
        guard let approach = selectedApproach, approach.isMissedApproachPlottable else {
          terrainPath = nil
          return
        }
        procedurePath = pathGenerator.missedApproachPath(
          from: approach.missedApproachLegs,
          startCoordinate: thresholdCoord,
          startAltitudeFt: fieldElevationFt
        )
      case .vectors:
        procedurePath = pathGenerator.headingPath(
          from: thresholdCoord,
          magneticDirection: vectorHeading,
          isHeading: true,
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

  // MARK: - Types

  private struct ComputationInputs: Equatable {
    let runwayName: String
    let weightLb: Double
    let slpInHg: Double
    let aircraftType: AircraftType
    let useRegressionModel: Bool
    let goAroundType: GoAroundType
    let approachID: String?
    let vectorHeadingDeg: Double
    let airportID: String
    let windsHash: Int
    let terrainRevision: Int
  }

  enum GoAroundType: String, CaseIterable, Identifiable {
    case publishedMissed, vectors

    var id: String { rawValue }

    var label: String {
      switch self {
        case .publishedMissed: "Published Missed"
        case .vectors: "Vectors"
      }
    }
  }
}

#Preview {
  PreviewView(insert: .KOAK) { helper in
    let runway = try helper.load(airportID: "OAK", runway: "28L")!
    helper.setLanding(runway: runway)

    return NavigationStack {
      GoAroundProfileView()
    }
    .environment(LandingPerformanceViewModel(container: helper.container))
    .environment(WeatherViewModel(operation: .landing, container: helper.container))
  }
}
