import SF50_Shared
import SwiftData
import SwiftUI

struct NearestView: View {
  var onSelect: (Airport) -> Void

  @Environment(\.modelContext)
  private var modelContext

  @Environment(\.locationStreamer)
  private var locationStreamer

  @Environment(\.scenePhase)
  private var scenePhase

  @State private var nearestAirports: NearestAirportViewModel?

  var body: some View {
    Group {
      // A broken stream outranks any availability state, and the view model only
      // samples the streamer’s error once, at init.
      if let error = locationStreamer.error {
        LocationErrorView(error: error)
      } else {
        NearestAvailabilityView(
          availability: locationStreamer.availability,
          viewModel: nearestAirports,
          onSelect: onSelect
        )
      }
    }
    .task {
      await locationStreamer.start()

      // Disappearing cancels this task but does not stop its body from running. A view torn
      // down before this point has already had its `onDisappear`, which found nothing to
      // release — so anything opened here would stay open for good.
      guard !Task.isCancelled else {
        await locationStreamer.stop()
        return
      }

      nearestAirports = .init(
        container: modelContext.container,
        locationStreamer: locationStreamer
      )
    }
    .onDisappear {
      nearestAirports?.cancel()
      nearestAirports = nil
      Task {
        await locationStreamer.stop()
      }
    }
    .onChange(of: scenePhase) { _, newPhase in
      // Someone who granted access in Settings comes back to a refusal that is no
      // longer true. Core Location only revises it on a fresh stream.
      guard newPhase == .active, locationStreamer.availability?.deniesAuthorization == true
      else { return }
      Task {
        await locationStreamer.retry()
      }
    }
  }
}

private struct NearestAvailabilityView: View {
  let availability: LocationAvailability?
  let viewModel: NearestAirportViewModel?
  var onSelect: (Airport) -> Void

  var body: some View {
    switch availability {
      case nil:
        ProgressView("Finding your location…")
      case .requestingAuthorization:
        LocationPermissionPromptView()
      case .authorizationDenied:
        LocationDeniedView(reason: .app)
      case .authorizationDeniedGlobally:
        LocationDeniedView(reason: .deviceWide)
      case .authorizationRestricted:
        LocationDeniedView(reason: .restricted)
      case .locationUnavailable:
        List {
          Text("Unable to determine location.")
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
        }
      case .available:
        NearestAirportList(viewModel: viewModel, onSelect: onSelect)
    }
  }
}

private struct NearestAirportList: View {
  let viewModel: NearestAirportViewModel?
  var onSelect: (Airport) -> Void

  var body: some View {
    if let viewModel {
      if let error = viewModel.error {
        LocationErrorView(error: error)
      } else if viewModel.airports.isEmpty {
        List {
          Text("No nearby airports.")
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
        }
      } else {
        List(viewModel.airports) { (airport: Airport) in
          AirportRow(airport: airport, showFavoriteButton: true)
            .onTapGesture {
              onSelect(airport)
            }
            .accessibility(addTraits: .isButton)
            .accessibilityIdentifier("airportRow-\(airport.displayID)")
        }
      }
    } else {
      ProgressView("Finding your location…")
    }
  }
}

#Preview("Airports") {
  PreviewView(insert: .KOAK, .K1C9, .KSQL) { _ in
    return NearestView { _ in }
      .environment(\.locationStreamer, MockLocationStreamer())
  }
}

#Preview("No Airports") {
  PreviewView { _ in
    return NearestView { _ in }
      .environment(\.locationStreamer, MockLocationStreamer())
  }
}

#Preview("Awaiting Permission") {
  PreviewView { _ in
    return NearestView { _ in }
      .environment(
        \.locationStreamer,
        MockLocationStreamer(availability: .requestingAuthorization)
      )
  }
}

#Preview("Denied") {
  PreviewView { _ in
    return NearestView { _ in }
      .environment(\.locationStreamer, MockLocationStreamer(availability: .authorizationDenied))
  }
}
