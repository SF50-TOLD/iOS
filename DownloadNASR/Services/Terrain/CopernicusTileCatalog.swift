import Foundation

/// Errors that can occur while reading the Copernicus DEM tile lists.
enum CopernicusTileCatalogError: LocalizedError {
  case tileListUnavailable(product: CopernicusTileCatalog.Product, statusCode: Int?)

  var errorDescription: String? {
    String(localized: "Couldn’t read the Copernicus DEM tile list.")
  }

  var failureReason: String? {
    switch self {
      case .tileListUnavailable(let product, let statusCode?):
        String(
          localized:
            "The \(product.displayName) tile list returned HTTP status \(statusCode, format: .number)."
        )
      case .tileListUnavailable(let product, nil):
        String(localized: "The \(product.displayName) tile list could not be downloaded.")
    }
  }
}

/// Says where each one-degree terrain tile comes from.
///
/// Terrain is the surface an aircraft can hit: the water surface over the sea and lakes, and the
/// ground everywhere else, however far below sea level it lies. The Copernicus DEM is a surface
/// model with exactly that property — every water body sits at its surface — so it is the only
/// source. Sources that merge in bathymetry would put the terrain under the sea on its floor.
///
/// GLO-30 is used wherever it is published. GLO-90 is published for every GLO-30 tile and also
/// for the tiles withheld from GLO-30's public release, so it fills those. A tile neither product
/// publishes holds no land, which makes it open sea at sea level rather than missing data.
struct CopernicusTileCatalog: Sendable {

  // MARK: - Instance Properties

  private let publishedTiles: [Product: Set<TileCoordinates>]

  // MARK: - Type Methods

  /// Downloads each product's list of published tiles.
  static func load(using session: URLSession) async throws -> Self {
    var publishedTiles: [Product: Set<TileCoordinates>] = [:]
    for product in Product.allCases {
      publishedTiles[product] = try await product.publishedTiles(using: session)
    }
    return .init(publishedTiles: publishedTiles)
  }

  // MARK: - Instance Methods

  /// Where to read the tile whose southwest corner is `tile`.
  func source(for tile: TileCoordinates) -> TileSource {
    let product = Product.allCases.first { publishedTiles[$0]?.contains(tile) == true }
    return product.map { .copernicus($0.tileURL(for: tile)) } ?? .openSea
  }

  // MARK: - Nested Types

  /// A Copernicus DEM product published on AWS open data.
  enum Product: CaseIterable, Sendable {
    case glo30
    case glo90

    /// The product's name as ESA publishes it.
    var displayName: String {
      switch self {
        case .glo30: "GLO-30"
        case .glo90: "GLO-90"
      }
    }

    /// The public bucket holding the product's tiles.
    private var bucketURL: URL {
      switch self {
        case .glo30: URL(string: "https://copernicus-dem-30m.s3.amazonaws.com")!
        case .glo90: URL(string: "https://copernicus-dem-90m.s3.amazonaws.com")!
      }
    }

    /// Resolution code in the product's tile names, in tenths of an arc-second.
    private var resolutionCode: String {
      switch self {
        case .glo30: "10"
        case .glo90: "30"
      }
    }

    /// Where a tile is published, e.g. `…/Copernicus_DSM_COG_10_N45_00_W123_00_DEM/…DEM.tif`.
    func tileURL(for tile: TileCoordinates) -> URL {
      let name = "Copernicus_DSM_COG_\(resolutionCode)_\(tile.copernicusName)_DEM"
      return bucketURL.appending(components: name, "\(name).tif")
    }

    /// Reads the product's `tileList.txt`, one tile name per line.
    fileprivate func publishedTiles(using session: URLSession) async throws -> Set<TileCoordinates>
    {
      let listURL = bucketURL.appending(component: "tileList.txt")
      let data: Data, response: URLResponse
      do {
        (data, response) = try await session.data(from: listURL)
      } catch {
        throw CopernicusTileCatalogError.tileListUnavailable(product: self, statusCode: nil)
      }
      let statusCode = (response as? HTTPURLResponse)?.statusCode
      guard statusCode == 200, let text = String(bytes: data, encoding: .utf8) else {
        throw CopernicusTileCatalogError.tileListUnavailable(product: self, statusCode: statusCode)
      }
      return Set(
        text.split(whereSeparator: \.isNewline).compactMap(
          TileCoordinates.init(copernicusTileName:)
        )
      )
    }
  }
}

/// Where one tile's elevations come from.
enum TileSource: Sendable {
  /// A Copernicus GeoTIFF to download.
  case copernicus(URL)
  /// Open sea, whose surface is at sea level.
  case openSea

  var isOpenSea: Bool {
    if case .openSea = self { true } else { false }
  }
}
