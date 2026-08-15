import SF50_Shared
import SwiftUI

struct WeatherSource: View {
  @Environment(WeatherViewModel.self)
  private var weather

  private var downloadButtonTitle: String {
    if weather.error != nil { return String(localized: "Try Again") }
    switch weather.conditions.source {
      case .entered: return String(localized: "Use Downloaded Weather")
      default: return String(localized: "Update Weather")
    }
  }

  private var formattedForecast: Loadable<String?> {
    return weather.TAF.map { forecast in
      guard let forecast else { return nil }
      let words = forecast.split(separator: " ")
      var formatted = [[String]]()

      formatted.append([])
      for word in words {
        if word.starts(with: "FM") || word == "BECMG" {
          formatted.append([])
        }
        formatted[formatted.count - 1].append(String(word))
      }

      return formatted.map { $0.joined(separator: " ") }.joined(separator: "\n  ")
    }
  }

  var body: some View {
    Section {
      HStack {
        switch weather.conditions.source {
          case .downloaded(let providers):
            Text("Using downloaded weather from \(providers.localizedDescription)")
              .font(.subheadline)
          case .entered:
            Text("Using your custom weather")
              .font(.subheadline)
          case .ISA:
            if weather.error != nil {
              Text("Couldn’t load weather — using ISA")
                .font(.subheadline)
                .foregroundStyle(.red)
            } else {
              Text("Using ISA weather")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }

        Spacer()
        Button {
          Task { await weather.load(force: true) }
        } label: {
          Text(downloadButtonTitle)
            .foregroundStyle(Color.accentColor).bold()
        }.accessibilityIdentifier("updateWeatherButton")
      }

      if weather.METAR.hasValue {
        RawWeather(rawText: weather.METAR)
      }
      if weather.TAF.hasValue {
        RawWeather(rawText: formattedForecast)
      }
    } header: {
      Text("Source")
    } footer: {
      // A footer rather than a row: these credit the section rather than being weather data of
      // their own, and a footer already sits outside the section's box.
      WeatherCredits(providers: weather.conditions.source.providers)
    }
  }
}

#Preview("NWS weather") {
  PreviewView(insert: .KOAK) { preview in
    let runway = try preview.load(airportID: "OAK", runway: "28R")!
    preview.setTakeoff(runway: runway)

    let mockLoader = MockWeatherLoader(
      mockMETAR: .value(preview.METARString),
      mockTAF: .value(preview.TAFString)
    )
    let weatherViewModel = WeatherViewModel(
      operation: .takeoff,
      container: preview.container,
      loader: mockLoader
    )

    return List { WeatherSource() }
      .environment(weatherViewModel)
      .task { await mockLoader.setMockConditions(.value(preview.NWS)) }
  }
}

#Preview("Weather from several services") {
  PreviewView(insert: .KOAK) { preview in
    let runway = try preview.load(airportID: "OAK", runway: "28R")!
    preview.setTakeoff(runway: runway)

    let mockLoader = MockWeatherLoader(
      mockConditions: .value(preview.augmented),
      mockMETAR: .value(preview.METARString)
    )
    let weatherViewModel = WeatherViewModel(
      operation: .takeoff,
      container: preview.container,
      loader: mockLoader
    )

    return List { WeatherSource() }
      .environment(weatherViewModel)
  }
}

#Preview("Custom weather") {
  PreviewView(insert: .KOAK) { preview in
    let runway = try preview.load(airportID: "OAK", runway: "28R")!
    preview.setTakeoff(runway: runway)

    let mockLoader = MockWeatherLoader(mockConditions: .value(preview.lightWinds))
    let weatherViewModel = WeatherViewModel(
      operation: .takeoff,
      container: preview.container,
      loader: mockLoader
    )

    return List { WeatherSource() }
      .environment(weatherViewModel)
  }
}

#Preview("Reset due to error") {
  PreviewView(insert: .KOAK) { preview in
    let runway = try preview.load(airportID: "OAK", runway: "28R")!
    preview.setTakeoff(runway: runway)

    let httpResponse = HTTPURLResponse(
      url: URL(string: "https://example.com")!,
      statusCode: 500,
      httpVersion: nil,
      headerFields: nil
    )!
    let mockLoader = MockWeatherLoader(mockError: WeatherLoader.Errors.badResponse(httpResponse))
    let weatherViewModel = WeatherViewModel(
      operation: .takeoff,
      container: preview.container,
      loader: mockLoader
    )

    return List { WeatherSource() }
      .environment(weatherViewModel)
  }
}

#Preview("Observation error") {
  PreviewView(insert: .KOAK) { preview in
    let runway = try preview.load(airportID: "OAK", runway: "28R")!
    preview.setTakeoff(runway: runway)

    let httpResponse = HTTPURLResponse(
      url: URL(string: "https://example.com")!,
      statusCode: 500,
      httpVersion: nil,
      headerFields: nil
    )!
    let mockLoader = MockWeatherLoader(
      mockMETAR: .error(WeatherLoader.Errors.badResponse(httpResponse))
    )
    let weatherViewModel = WeatherViewModel(
      operation: .takeoff,
      container: preview.container,
      loader: mockLoader
    )

    return List { WeatherSource() }
      .environment(weatherViewModel)
  }
}

#Preview("Forecast error") {
  PreviewView(insert: .KOAK) { preview in
    let runway = try preview.load(airportID: "OAK", runway: "28R")!
    preview.setTakeoff(runway: runway)

    let httpResponse = HTTPURLResponse(
      url: URL(string: "https://example.com")!,
      statusCode: 500,
      httpVersion: nil,
      headerFields: nil
    )!
    let mockLoader = MockWeatherLoader(
      mockTAF: .error(WeatherLoader.Errors.badResponse(httpResponse))
    )
    let weatherViewModel = WeatherViewModel(
      operation: .takeoff,
      container: preview.container,
      loader: mockLoader
    )

    return List { WeatherSource() }
      .environment(weatherViewModel)
  }
}
