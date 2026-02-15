import CoreLocation
import Sentry
import SwiftData

/// View model for finding airports near the user's current location.
///
/// ``NearestAirportViewModel`` uses CoreLocation to track the user's position
/// and queries SwiftData for nearby airports. Results are sorted by distance
/// and limited to the closest 10 airports within a 50 nautical mile radius.
///
/// ## Location Updates
///
/// The view model subscribes to location updates via ``LocationStreamer``
/// and automatically updates the airport list when the user moves.
///
/// ## Usage
///
/// ```swift
/// let viewModel = NearestAirportViewModel(
///     container: modelContainer,
///     locationStreamer: CoreLocationStreamer()
/// )
///
/// // Access nearest airports
/// ForEach(viewModel.airports) { airport in
///     Text(airport.name)
/// }
/// ```
///
/// ## See Also
///
/// - ``LocationStreamer``
/// - ``CoreLocationStreamer``
@Observable
@MainActor
public class NearestAirportViewModel {
  /// Search radius in nautical miles
  private static let searchRadius = 50.0

  /// Nautical miles per degree of latitude (1° = 60 NM).
  private static let nauticalMilesPerDegree = 60.0

  /// Minimum cosine of latitude to avoid divide-by-zero near poles.
  private static let minimumCosineLatitude = 0.00001

  /// Maximum number of nearest airports to return.
  private static let maxResults = 10

  /// Airports sorted by distance from user's current location (max 10)
  public private(set) var airports: [Airport] = []

  /// Error from location services or database query
  public private(set) var error: Error?

  /// Current user location
  private var location: CLLocation? {
    didSet { updateAirports() }
  }

  /// Location service provider
  private let streamer: any LocationStreamer

  /// SwiftData container for airport queries
  private let container: ModelContainer

  /// Background task for location updates
  private var updateTask: Task<Void, Never>?

  /// Background task for airport fetch
  private var fetchTask: Task<Void, Never>?

  /**
   * Creates a view model with the specified data container and location streamer.
   *
   * - Parameters:
   *   - container: SwiftData model container for airport queries.
   *   - locationStreamer: Location service provider for tracking user position.
   */
  public init(container: ModelContainer, locationStreamer: any LocationStreamer) {
    self.streamer = locationStreamer
    self.container = container

    updateTask = Task {
      await streamer.start()

      // Get initial values
      location = streamer.location
      error = streamer.error

      // Subscribe to location updates
      for await newLocation in streamer.locationUpdates() where !Task.isCancelled {
        await MainActor.run {
          self.location = newLocation
          self.error = nil
        }
      }
    }
  }

  private func updateAirports() {
    guard let location else {
      airports = []
      return
    }

    let capturedLocation = location
    let container = self.container

    // Build predicate bounds on main thread (cheap math)
    let lat = capturedLocation.coordinate.latitude
    let lon = capturedLocation.coordinate.longitude

    let latDelta = Self.searchRadius / Self.nauticalMilesPerDegree
    let clampedMinLat = max(-90.0, lat - latDelta)
    let clampedMaxLat = min(90.0, lat + latDelta)

    let cosLat = cos(lat * .pi / 180)
    // Avoid divide-by-zero near poles
    let lonDelta =
      Self.searchRadius / (Self.nauticalMilesPerDegree * max(cosLat, Self.minimumCosineLatitude))
    var minLon = lon - lonDelta
    var maxLon = lon + lonDelta

    // Wrap around at -180/180
    if minLon < -180.0 { minLon += 360.0 }
    if maxLon > 180.0 { maxLon -= 360.0 }

    let wrapAround = minLon >= maxLon
    let maxResults = Self.maxResults

    fetchTask?.cancel()
    fetchTask = Task.detached {
      do {
        let context = ModelContext(container)

        let predicate: Predicate<Airport>
        if wrapAround {
          // Wrap-around case: split longitude range
          predicate = #Predicate { airport in
            airport._latitude >= clampedMinLat && airport._latitude <= clampedMaxLat
              && (airport._longitude >= minLon || airport._longitude <= maxLon)
          }
        } else {
          // Normal case: no wrap-around
          predicate = #Predicate { airport in
            airport._latitude >= clampedMinLat && airport._latitude <= clampedMaxLat
              && airport._longitude >= minLon && airport._longitude <= maxLon
          }
        }

        let descriptor = FetchDescriptor(predicate: predicate)
        let unsortedAirports = try context.fetch(descriptor)

        let sorted =
          unsortedAirports
          .map { ($0, capturedLocation.distance(from: $0.location)) }
          .sorted { $0.1 < $1.1 }
          .prefix(maxResults)
          .map(\.0)

        guard !Task.isCancelled else { return }
        await MainActor.run {
          self.airports = sorted
        }
      } catch {
        guard !Task.isCancelled else { return }
        await MainActor.run {
          SentrySDK.capture(error: error)
          self.error = error
        }
      }
    }
  }
}
