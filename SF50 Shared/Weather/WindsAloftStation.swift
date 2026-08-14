import CoreLocation
import Foundation

/// A location the NWS publishes a winds aloft forecast for.
///
/// The winds aloft bulletins identify each forecast location by a three-character identifier and
/// nothing else, so the coordinates come from Appendix A of NWS Instruction 10-812, transcribed
/// into a bundled table. They cannot be resolved from the nav database: the forecast locations are
/// a mix of airports, VORs — `EMI` is Westminster VORTAC, `CZI` is Crazy Woman — and oceanic grid
/// points such as `H51` and `5AB`, which are neither.
///
/// An identifier is also not enough to decide that a forecast belongs to an airport. NWS names each
/// location by its FAA or VOR identifier, but frequently forecasts for the VOR rather than the
/// field: `DEN` is 10 NM from Denver International and `MSP` is 16 NM from Minneapolis-St Paul. A
/// match is therefore confirmed by position rather than taken on the identifier alone.
public struct WindsAloftStation: Sendable, Hashable, Locatable, Decodable {

  /// The three-character identifier the bulletins report this location under.
  public let id: String

  /// The location's latitude, in degrees.
  public let latitude: Double

  /// The location's longitude, in degrees.
  public let longitude: Double

  /// The location's position.
  public var coordinate: CLLocationCoordinate2D {
    .init(latitude: latitude, longitude: longitude)
  }
}

// MARK: - The published forecast locations

extension WindsAloftStation {

  /// Every location the NWS publishes a winds aloft forecast for, by identifier.
  ///
  /// Transcribed from Appendix A of
  /// [NWS Instruction 10-812](https://www.weather.gov/media/directives/010_pdfs/pd01008012curr.pdf),
  /// which is the only authoritative list of these coordinates — there is no machine-readable
  /// source, and the Aviation Weather station API covers METAR and TAF sites only.
  ///
  /// Three rows are corrected, each noted in the file: the directive prints Berlin's and one Gulf
  /// of Alaska point's longitude without its minus sign, placing them in Mongolia and west of Attu,
  /// and gives San Antonio a latitude 54 NM south of the field. Every row around each of the two
  /// unsigned ones carries the sign it is missing. The list changes rarely — the directive has been
  /// effective since September 2022 — so a bulletin reporting an identifier absent from this table
  /// is logged as the signal that it needs revisiting.
  public static let all: [String: Self] = {
    guard
      let url = Bundle(for: BundleAnchor.self)
        .url(forResource: "winds-aloft-stations", withExtension: "json", subdirectory: "Data")
    else {
      fatalError("Could not find winds-aloft-stations.json")
    }

    do {
      let stations = try JSONDecoder().decode([Self].self, from: try Data(contentsOf: url))
      return .init(uniqueKeysWithValues: stations.map { ($0.id, $0) })
    } catch {
      fatalError("Could not load winds-aloft-stations.json: \(error)")
    }
  }()
}

/// Resolves the framework bundle the station table is packaged in.
///
/// `Bundle.main` is the app, not this framework, and `Bundle(for:)` needs a class defined
/// alongside the resource.
private final class BundleAnchor {}
