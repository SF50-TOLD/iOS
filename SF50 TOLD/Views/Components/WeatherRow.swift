import Defaults
import SF50_Shared
import SwiftUI

private let maxDA = Measurement(value: 15_000, unit: UnitLength.feet)

struct WeatherRow: View {
  var elevation: Measurement<UnitLength>

  @Environment(\.aircraftType)
  private var aircraftType

  @Environment(WeatherViewModel.self)
  private var weather

  private var limitations: Limitations.Type {
    aircraftType.limitations
  }

  var body: some View {
    if weather.isLoading {
      HStack {
        ProgressView().progressViewStyle(CircularProgressViewStyle())
        Text("Loading weather…").foregroundStyle(.secondary)
          .accessibilityIdentifier("loadingWeatherLabel")
      }
    } else if weather.conditions.source == .ISA {
      if weather.error != nil {
        Text("Couldn’t load weather — using ISA").foregroundStyle(.red)
          .accessibilityIdentifier("loadingWeatherFailedLabel")
      } else {
        Text("No weather — using ISA").foregroundStyle(.secondary)
          .accessibilityIdentifier("noWeatherLabel")
      }
    } else {
      LoadedWeatherRow(
        conditions: weather.conditions,
        elevation: elevation,
        minTemperature: limitations.minTemperature,
        maxTemperature: limitations.maxTemperature
      )
    }
  }
}

private struct LoadedWeatherRow: View {
  var conditions: Conditions
  var elevation: Measurement<UnitLength>

  var minTemperature: Measurement<UnitTemperature>?
  var maxTemperature: Measurement<UnitTemperature>?

  @Default(.temperatureUnit)
  private var temperatureUnit

  @Default(.heightUnit)
  private var heightUnit

  var windColor: Color { conditions.source == .ISA ? .secondary : .primary }
  var tempColor: Color {
    if let maxTemperature,
      conditions.temperature(at: elevation) > maxTemperature
    {
      return .red
    }
    if let minTemperature,
      conditions.temperature(at: elevation) < minTemperature
    {
      return .red
    }
    return conditions.source == .ISA ? .secondary : .primary
  }
  var DAColor: Color {
    if conditions.densityAltitude(elevation: elevation) > maxDA {
      return .red
    }
    return conditions.source == .ISA ? .secondary : .primary
  }

  var body: some View {
    HStack(spacing: 20) {
      Label {
        WindText(conditions: conditions)
      } icon: {
        Image(systemName: "wind")
      }
      .accessibilityLabel("Wind")
      .foregroundStyle(windColor)

      Label {
        Text(
          conditions.temperature(at: elevation).converted(to: temperatureUnit),
          format: .temperature
        )
      } icon: {
        Image(systemName: "thermometer")
      }
      .accessibilityLabel("Temperature")
      .foregroundStyle(tempColor)

      Label {
        Text(
          conditions.densityAltitude(elevation: elevation).converted(to: heightUnit),
          format: .height
        )
      } icon: {
        Image(systemName: "mountain.2")
      }
      .accessibilityLabel("Density Altitude")
      .foregroundStyle(DAColor)
    }
    .labelStyle(CompactLabelStyle())
    .font(.system(size: 14))
    .accessibilityIdentifier("weatherSummary")
  }
}

private struct WindText: View {
  var conditions: Conditions

  @Default(.speedUnit)
  private var speedUnit

  var body: some View {
    if conditions.windsCalm {
      Text("calm", comment: "wind speed")
    } else if let windDirection = conditions.windDirection,
      let windSpeed = conditions.windSpeed
    {
      Text(
        "\(windDirection.asHeading, format: .heading) @ \(windSpeed.converted(to: speedUnit), format: .speed)",
        comment: "wind direction @ speed"
      )
    } else {
      Text("calm", comment: "wind speed")
    }
  }
}

#Preview {
  PreviewView(insert: .KSQL) { preview in
    let url = URL(string: "https://example.com")!
    let httpResponse = HTTPURLResponse(
      url: url,
      statusCode: 404,
      httpVersion: "1.1",
      headerFields: [:]
    )!
    let badResponse = WeatherLoader.Errors.badResponse(httpResponse)

    let runway = try preview.load(airportID: "SQL", runway: "30")!
    preview.setTakeoff(runway: runway)

    let loadingLoader = MockWeatherLoader(mockConditions: .loading)
    let loadingWeather = WeatherViewModel(
      operation: .takeoff,
      container: preview.container,
      loader: loadingLoader
    )

    let errorLoader = MockWeatherLoader(mockConditions: .error(badResponse))
    let errorWeather = WeatherViewModel(
      operation: .takeoff,
      container: preview.container,
      loader: errorLoader
    )

    return List {
      Section("Weather") {
        let mockLoader = MockWeatherLoader()
        let weather = WeatherViewModel(
          operation: .takeoff,
          container: preview.container,
          loader: mockLoader
        )
        WeatherRow(elevation: .init(value: 0.0, unit: .feet))
          .environment(weather)
          .onAppear { weather.conditions = preview.lightWinds }
      }
      Section("High DA") {
        let mockLoader = MockWeatherLoader()
        let weather = WeatherViewModel(
          operation: .takeoff,
          container: preview.container,
          loader: mockLoader
        )
        WeatherRow(elevation: .init(value: 15_000.0, unit: .feet))
          .environment(weather)
          .onAppear { weather.conditions = preview.lightWinds }
      }
      Section("Below Min Temp") {
        let mockLoader = MockWeatherLoader()
        let weather = WeatherViewModel(
          operation: .takeoff,
          container: preview.container,
          loader: mockLoader
        )
        WeatherRow(elevation: .init(value: 0.0, unit: .feet))
          .environment(weather)
          .onAppear { weather.conditions = preview.veryCold }
      }
      Section("Above Max Temp") {
        let mockLoader = MockWeatherLoader()
        let weather = WeatherViewModel(
          operation: .takeoff,
          container: preview.container,
          loader: mockLoader
        )
        WeatherRow(elevation: .init(value: 0.0, unit: .feet))
          .environment(weather)
          .onAppear { weather.conditions = preview.veryHot }
      }
      Section("ISA") {
        let mockLoader = MockWeatherLoader()
        let weather = WeatherViewModel(
          operation: .takeoff,
          container: preview.container,
          loader: mockLoader
        )
        WeatherRow(elevation: .init(value: 0.0, unit: .feet))
          .environment(weather)
          .onAppear { weather.conditions = preview.ISA }
      }
      Section("Loading") {
        WeatherRow(elevation: .init(value: 0.0, unit: .feet))
          .environment(loadingWeather)
      }
      Section("Error") {
        WeatherRow(elevation: .init(value: 0.0, unit: .feet))
          .environment(errorWeather)
      }
    }
  }
}
