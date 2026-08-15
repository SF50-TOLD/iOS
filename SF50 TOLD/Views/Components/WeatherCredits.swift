import SF50_Shared
import SwiftUI
import WeatherKit

/// The credits owed to the services a weather report was drawn from.
///
/// Open-Meteo's CC-BY 4.0 licence asks for a credit linking back to it. Apple asks for its
/// trademark rather than its name — *"you must clearly display the Apple Weather trademark, as
/// well as the legal link to other data sources"* — so its mark is shown, linked to that page.
/// NWS data is public domain and asks for nothing, so a report drawn only from Aviation Weather
/// shows nothing here.
///
/// The mark is served by WeatherKit rather than bundled, so it is fetched at display time — once
/// per set of providers, since one attribution carries both the light and the dark cut and the
/// appearance only chooses between them.
struct WeatherCredits: View {
  /// How tall the Apple Weather mark is drawn — the caption size it sits beside, so the two read
  /// as one line of credits rather than the mark shouting over the text.
  @ScaledMetric(relativeTo: .caption)
  private var markHeight: CGFloat = 12

  /// The services that contributed.
  let providers: WeatherProviders

  @Environment(\.colorScheme)
  private var colorScheme

  @State private var attribution: WeatherAttribution?

  private var creditsOwed: Bool { !providers.isDisjoint(with: [.openMeteo, .weatherKit]) }

  private var markURL: URL? {
    guard let attribution else { return nil }
    return colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL
  }

  var body: some View {
    if creditsOwed {
      HStack(spacing: 12) {
        if providers.contains(.openMeteo) {
          Link("Open-Meteo", destination: WeatherProviders.openMeteoURL)
        }
        if providers.contains(.weatherKit) {
          appleWeatherMark
        }
      }
      // Aligned by the frame rather than a spacer, which collapses against the ideal width a
      // safe-area inset proposes to its content.
      .frame(maxWidth: .infinity, alignment: .trailing)
      .font(.caption)
      // The frame keeps something rendered while the mark loads. A view resolving to nothing has
      // no node for this to run on, which would keep the fetch that populates it from starting.
      //
      // Keyed on the providers: WeatherKit can join a report that already owed Open-Meteo a credit,
      // and the fetch has to run again for the mark to appear at all.
      .task(id: providers) { await loadAttribution() }
    }
  }

  @ViewBuilder private var appleWeatherMark: some View {
    if let attribution, let markURL {
      Link(destination: attribution.legalPageURL) {
        AsyncImage(url: markURL) { image in
          image.resizable().scaledToFit()
        } placeholder: {
          Color.clear
        }
        .frame(height: markHeight)
        .accessibilityLabel(attribution.serviceName)
      }
    }
  }

  private func loadAttribution() async {
    guard providers.contains(.weatherKit) else { return }
    attribution = try? await WeatherService.shared.attribution
  }
}

#Preview("Open-Meteo only") {
  // Shown the way it sits in `WeatherSource`: as the section's footer, outside its box.
  let providers: WeatherProviders = [.NWS, .openMeteo]
  return Form {
    Section {
      HStack {
        Text("Using downloaded weather from \(providers.localizedDescription)")
          .font(.subheadline)
        Spacer()
        Text("Update Weather").foregroundStyle(Color.accentColor).bold()
      }
    } header: {
      Text("Source")
    } footer: {
      WeatherCredits(providers: providers)
    }
  }
}

/// Covers the WeatherKit path, which the app itself reaches only when Open-Meteo can’t
/// answer. The mark and its legal link are fetched live, so this needs a network.
#Preview("Apple Weather") {
  // Shown the way it sits in `WeatherSource`: as the section's footer, outside its box.
  let providers: WeatherProviders = [.NWS, .weatherKit]
  return Form {
    Section {
      HStack {
        Text("Using downloaded weather from \(providers.localizedDescription)")
          .font(.subheadline)
        Spacer()
        Text("Update Weather").foregroundStyle(Color.accentColor).bold()
      }
    } header: {
      Text("Source")
    } footer: {
      WeatherCredits(providers: providers)
    }
  }
}

#Preview("Every service") {
  // Shown the way it sits in `WeatherSource`: as the section's footer, outside its box.
  let providers: WeatherProviders = [.NWS, .openMeteo, .weatherKit]
  return Form {
    Section {
      HStack {
        Text("Using downloaded weather from \(providers.localizedDescription)")
          .font(.subheadline)
        Spacer()
        Text("Update Weather").foregroundStyle(Color.accentColor).bold()
      }
    } header: {
      Text("Source")
    } footer: {
      WeatherCredits(providers: providers)
    }
  }
}

/// NWS data is public domain, so nothing should appear below the form.
#Preview("No credit required") {
  // Shown the way it sits in `WeatherSource`: as the section's footer, outside its box.
  let providers: WeatherProviders = .NWS
  return Form {
    Section {
      HStack {
        Text("Using downloaded weather from \(providers.localizedDescription)")
          .font(.subheadline)
        Spacer()
        Text("Update Weather").foregroundStyle(Color.accentColor).bold()
      }
    } header: {
      Text("Source")
    } footer: {
      WeatherCredits(providers: providers)
    }
  }
}
