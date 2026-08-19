import MeasurementKit
import SF50_Shared
import SwiftUI

/// The terrain profile chart, its weather layer controls, and the credits they owe.
///
/// Shared by the climb and go-around profile screens, which plot the same chart from the same
/// pipeline and differ only in what they say when there is nothing to plot yet.
struct TerrainProfileSection: View {

  // MARK: - Inputs

  /// The computed path, or `nil` while there is nothing to draw.
  let terrainPath: ProcedureTerrainPath?

  /// The climb profile the path was flown on, which the wind barbs are read from.
  let climbProfile: ClimbProfile?

  /// Whether a winds aloft forecast covers this flight.
  ///
  /// Taken from the forecast itself rather than inferred from the profile's winds: without one
  /// `ClimbProfileGenerator` synthesizes a calm column, and a chart full of calm circles would
  /// read as a report of still air rather than as the absence of a report.
  let hasWindsAloft: Bool

  /// The elevation of the departure or arrival airport.
  let fieldElevation: Measurement<UnitLength>

  /// The time the weather is wanted for.
  let time: Date

  /// Whether the path is still being computed.
  let isComputing: Bool

  /// Whether the path could not be computed at all.
  let pathFailed: Bool

  /// What to say before anything has been selected to plot.
  let noDataDescription: LocalizedStringKey

  @Environment(\.pathAtmosphereLoader)
  private var atmosphereLoader

  @State private var weatherLayer: WeatherProfileLayer
  @State private var showsWindBarbs: Bool
  @State private var atmosphereState = AtmosphereState.notLoaded

  private var atmosphere: PathAtmosphere? { atmosphereState.atmosphere }

  private var providers: WeatherProviders {
    weatherLayer.needsAtmosphere ? (atmosphere?.providers ?? []) : []
  }

  /// Whether the field layers have anything to draw.
  ///
  /// The fields are model data that has to be fetched; terrain, obstacles, and the winds aloft the
  /// path was flown on are already in hand. Planning a go-around in the air means the first are
  /// gone and the rest are not, so the picker offers only what it can actually show.
  private var fieldLayersAvailable: Bool {
    if let atmosphere { return !atmosphere.isEmpty }
    // Not yet attempted or still loading: keep them selectable rather than flickering disabled.
    return !atmosphereState.hasFailed
  }

  var body: some View {
    Section {
      if isComputing {
        ComputingRow()
      } else if let terrainPath {
        ProfileChart(
          terrainPath: terrainPath,
          fieldElevation: fieldElevation,
          atmosphere: atmosphere,
          climbProfile: climbProfile,
          weatherLayer: $weatherLayer,
          showsWindBarbs: $showsWindBarbs,
          fieldLayersAvailable: fieldLayersAvailable,
          hasWindsAloft: hasWindsAloft,
          providers: providers
        )
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
          description: Text(noDataDescription)
        )
      }
    } header: {
      Text("Terrain Profile")
    } footer: {
      ProfileFooter(
        hasPath: terrainPath != nil,
        hasWindsAloft: hasWindsAloft,
        atmosphereState: atmosphereState,
        weatherLayer: weatherLayer,
        temperatureRange: temperatureRange,
        showsFreezingLevel: showsFreezingLevel
      )
    }
    .task(id: weatherRequest) { await loadAtmosphere() }
    .onChange(of: fieldLayersAvailable) { _, available in
      if !available { weatherLayer = .none }
    }
    // A forecast that stops covering this flight leaves the barbs nothing to read, and the
    // synthesized calm column behind them would draw as a report of still air.
    .onChange(of: hasWindsAloft, initial: true) { _, available in
      if !available { showsWindBarbs = false }
    }
  }

  // MARK: - Computed Properties

  private var temperatureRange: ClosedRange<Measurement<UnitTemperature>>? {
    guard weatherLayer == .temperature, let terrainPath, let atmosphere else { return nil }
    return atmosphere.temperatureRange(
      from: fieldElevation,
      to: visibleCeiling(of: terrainPath)
    )
  }

  /// Whether the chart is actually ruling a freezing level, and so wants a key for it.
  ///
  /// Asked of the same sampling the chart draws from, so the key can't appear for a line that
  /// falls outside the visible band.
  private var showsFreezingLevel: Bool {
    guard weatherLayer == .temperature || weatherLayer == .icing,
      let terrainPath,
      let atmosphere
    else { return false }

    return !atmosphere.freezingLevel(
      toDistanceNM: terrainPath.totalDistanceNM,
      between: fieldElevation,
      and: visibleCeiling(of: terrainPath)
    ).isEmpty
  }

  /// What the atmosphere is loaded for; a change reloads it.
  ///
  /// Deliberately not conditioned on a field layer being chosen. Whether the layers can be served
  /// has to be known before the picker is opened, or it cannot disable what it cannot show — and
  /// the fetch is small, cached, and shared with whichever layer is picked next.
  private var weatherRequest: WeatherRequest? {
    guard let terrainPath, !terrainPath.points.isEmpty else { return nil }
    return .init(
      points: terrainPath.points.map {
        .init(coordinate: $0.coordinate, distanceNM: $0.distanceNM)
      },
      time: time
    )
  }

  // MARK: - Initialization

  /// Creates the section.
  ///
  /// The two weather selections are inputs only so a preview can open on one; the chart owns them
  /// from then on. In the app both take their defaults and the section opens showing neither.
  init(
    terrainPath: ProcedureTerrainPath?,
    climbProfile: ClimbProfile?,
    hasWindsAloft: Bool,
    fieldElevation: Measurement<UnitLength>,
    time: Date,
    isComputing: Bool,
    pathFailed: Bool,
    noDataDescription: LocalizedStringKey,
    initialWeatherLayer: WeatherProfileLayer = .none,
    initialShowsWindBarbs: Bool = false
  ) {
    self.terrainPath = terrainPath
    self.climbProfile = climbProfile
    self.hasWindsAloft = hasWindsAloft
    self.fieldElevation = fieldElevation
    self.time = time
    self.isComputing = isComputing
    self.pathFailed = pathFailed
    self.noDataDescription = noDataDescription
    _weatherLayer = .init(initialValue: initialWeatherLayer)
    _showsWindBarbs = .init(initialValue: initialShowsWindBarbs)
  }

  // MARK: - Loading

  private func visibleCeiling(of terrainPath: ProcedureTerrainPath) -> Measurement<UnitLength> {
    terrainPath.maxAltitude(fieldElevation: fieldElevation)
  }

  private func loadAtmosphere() async {
    guard let weatherRequest else {
      atmosphereState = .notLoaded
      return
    }

    atmosphereState = .loading
    do {
      atmosphereState = .loaded(
        try await atmosphereLoader.atmosphere(
          along: weatherRequest.points,
          at: weatherRequest.time
        )
      )
    } catch {
      guard !Task.isCancelled else { return }
      atmosphereState = .failed(.init(error))
    }
  }

  // MARK: - Subtypes

  private struct WeatherRequest: Equatable {
    let points: [PathAtmosphereLoader.PathPoint]
    let time: Date
  }
}

/// How far the atmosphere behind the field layers has got.
private enum AtmosphereState {
  case notLoaded
  case loading
  case loaded(PathAtmosphere)
  case failed(PathAtmosphereLoader.Failure)

  /// What was loaded, if the load has finished and succeeded.
  var atmosphere: PathAtmosphere? {
    guard case .loaded(let atmosphere) = self else { return nil }
    return atmosphere
  }

  var isLoading: Bool {
    if case .loading = self { return true }
    return false
  }

  var hasFailed: Bool {
    if case .failed = self { return true }
    return false
  }
}

/// The spinner shown while the path is still being computed.
private struct ComputingRow: View {
  var body: some View {
    HStack {
      Spacer()
      TerrainComputingIndicator()
      Spacer()
    }
    .padding()
  }
}

/// The chart itself, with the weather controls and the credits inside its box.
private struct ProfileChart: View {

  // MARK: - Constants

  private static let heightPts: CGFloat = 300

  /// How much room above the chart the weather controls sit in: their own height and no more, so
  /// the chart's axis label supplies the gap below them.
  private static let controlsHeadroomPts: CGFloat = 26

  // MARK: - Inputs

  let terrainPath: ProcedureTerrainPath
  let fieldElevation: Measurement<UnitLength>
  let atmosphere: PathAtmosphere?
  let climbProfile: ClimbProfile?

  @Binding var weatherLayer: WeatherProfileLayer
  @Binding var showsWindBarbs: Bool

  let fieldLayersAvailable: Bool
  let hasWindsAloft: Bool
  let providers: WeatherProviders

  var body: some View {
    TerrainProfileChartView(
      terrainPath: terrainPath,
      fieldElevation: fieldElevation,
      atmosphere: atmosphere,
      climbProfile: climbProfile,
      weatherLayer: weatherLayer,
      showsWindBarbs: showsWindBarbs
    )
    .frame(height: Self.heightPts)
    // Headroom for the controls, so the chart's top gridline clears them rather than running right
    // under the pills.
    .padding(.top, Self.controlsHeadroomPts)
    .overlay(alignment: .topLeading) {
      ProfileWeatherControls(
        layer: $weatherLayer,
        showsWindBarbs: $showsWindBarbs,
        fieldLayersAvailable: fieldLayersAvailable,
        hasWindsAloft: hasWindsAloft
      )
    }
    // The credit is owed by the layer drawn here, and the corner below the axis is the only part of
    // the chart's box nothing else occupies.
    .overlay(alignment: .bottomTrailing) {
      WeatherCredits(providers: providers)
    }
  }
}

/// What the section says below the chart: the key to the layer showing, and what the chart can't
/// draw.
///
/// A field layer that can't be served is left to the weather pill, which goes dead when there is no
/// atmosphere behind it. Saying it here as well would explain in prose what the control already
/// shows.
private struct ProfileFooter: View {

  let hasPath: Bool
  let hasWindsAloft: Bool
  let atmosphereState: AtmosphereState
  let weatherLayer: WeatherProfileLayer
  let temperatureRange: ClosedRange<Measurement<UnitTemperature>>?
  let showsFreezingLevel: Bool

  private var atmosphere: PathAtmosphere? { atmosphereState.atmosphere }

  private var showsLegend: Bool {
    weatherLayer.needsAtmosphere && atmosphere?.isEmpty == false
  }

  private var isTruncated: Bool {
    atmosphere?.isTruncated == true && weatherLayer.needsAtmosphere
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if hasPath && !hasWindsAloft {
        Text("No winds aloft forecast covers this time, so there are no wind barbs to draw.")
      }
      if hasPath && atmosphereState.isLoading {
        Text("Loading weather layers…")
      }
      if isTruncated {
        Text("The path runs beyond the weather sampled for it; the layer stops short of its end.")
      }
      if showsLegend {
        WeatherLayerLegend(
          layer: weatherLayer,
          temperatureRange: temperatureRange,
          showsFreezingLevel: showsFreezingLevel
        )
      }
    }
  }
}

// periphery:ignore - consumed only by the #Preview macros below
private struct SectionPreview: View {
  var outcome: PreviewPathAtmosphereLoader.Outcome = .loaded(.previewMultiColumn)
  var hasWindsAloft = true
  var layer = WeatherProfileLayer.none
  var showsWindBarbs = false

  var body: some View {
    List {
      TerrainProfileSection(
        terrainPath: .preview,
        climbProfile: .preview,
        hasWindsAloft: hasWindsAloft,
        fieldElevation: .zero,
        time: .now,
        isComputing: false,
        pathFailed: false,
        noDataDescription: "Select a departure procedure to view terrain profile.",
        initialWeatherLayer: layer,
        initialShowsWindBarbs: showsWindBarbs
      )
    }
    .environment(\.pathAtmosphereLoader, PreviewPathAtmosphereLoader(outcome))
  }
}

#Preview("No layer") {
  SectionPreview()
}

#Preview("Temperature") {
  SectionPreview(layer: .temperature)
}

#Preview("Clouds") {
  SectionPreview(layer: .clouds)
}

#Preview("Icing") {
  SectionPreview(layer: .icing)
}

#Preview("Wind barbs") {
  SectionPreview(showsWindBarbs: true)
}

/// The go-around case: in the air with no connection. The weather layers can't be fetched and are
/// offered as disabled, but terrain, obstacles, and the winds aloft still plot.
#Preview("No connection") {
  SectionPreview(outcome: .offline, showsWindBarbs: true)
}

#Preview("Service unavailable") {
  SectionPreview(outcome: .unavailable)
}

/// No forecast reached this flight, so there is nothing for the barbs to draw.
#Preview("No winds aloft") {
  SectionPreview(outcome: .offline, hasWindsAloft: false)
}

/// The service answered, but no column over this path reported a usable level. Nothing says so but
/// the dead weather pill.
#Preview("Nothing reported") {
  SectionPreview(outcome: .loaded(.init(columns: [], providers: [])))
}
