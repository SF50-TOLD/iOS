import Foundation
import Logging
import SF50_Shared

/// Errors that can occur during SRTM processing.
enum SRTMProcessorError: LocalizedError {
  case downloadFailed(tile: String, error: any Error)
  case unexpectedStatus(tile: String, statusCode: Int?)
  case tilesFailed(region: String, count: Int)
  case compressionFailed(any Error)
  case missingRegions([TerrainRegion])

  var errorDescription: String? {
    String(localized: "Terrain processing failed.")
  }

  var failureReason: String? {
    switch self {
      case .downloadFailed(let tile, let error):
        return String(localized: "Failed to download tile “\(tile)”: \(error.localizedDescription)")
      case .unexpectedStatus(let tile, let statusCode?):
        return String(
          localized: "Tile “\(tile)” returned HTTP status \(statusCode, format: .number)."
        )
      case .unexpectedStatus(let tile, nil):
        return String(localized: "Tile “\(tile)” returned no HTTP response.")
      case .tilesFailed(let region, let count):
        return String(
          localized: "\(count, format: .number) tiles in \(region) could not be read."
        )
      case .compressionFailed(let error):
        return String(localized: "Failed to compress terrain data: \(error.localizedDescription)")
      case .missingRegions(let regions):
        let names = regions.map(\.displayName)
        return String(
          localized:
            "Cannot generate manifest: Missing payloads for regions: \(names, format: .list(type: .and)). Copy existing .srtm files to the output directory or select these regions for processing."
        )
    }
  }
}

/// Orchestrates the complete SRTM terrain data processing pipeline.
///
/// ``SRTMProcessor`` coordinates the downloading, parsing, and output of terrain data in the
/// SRTM-derived binary format the app reads:
///
/// 1. Download each tile of the selected regions, and resample it onto the SRTM3 grid
/// 2. Combine the tiles into one binary payload per region
/// 3. Generate terrain manifest
/// 4. Package each region as a Background Assets asset pack
/// 5. Upload to CloudFlare R2 (if configured)
///
/// ## Data Source
///
/// Every tile comes from the Copernicus DEM, as ``CopernicusTileCatalog`` describes: a surface
/// model, so terrain over water is the water's surface.
///
/// ## Progress Tracking
///
/// The processor uses callbacks to report progress:
/// - `onProgress`: Called when progress state changes
/// - `onUploadError`: Called if R2 upload fails
/// - `onLog`: Called for each log entry
actor SRTMProcessor {

  // MARK: - Type Properties

  /// Maximum tiles in flight at once, each being downloaded, parsed or compressed.
  ///
  /// A parsed Copernicus tile briefly holds several hundred megabytes, which bounds this more
  /// tightly than the bucket's appetite for concurrent requests does.
  private static let maxConcurrentTiles = 8

  /// Attempts at downloading one tile before the region fails.
  private static let maxDownloadAttempts = 4

  /// Pause after a failed download attempt, multiplied by the attempt number.
  private static let downloadRetryDelay = Duration.seconds(5)

  /// Samples along each side of an output tile: the SRTM3 grid, both edges included.
  private static let samplesPerSide = 1201

  /// How a run's release stamp is written, e.g. `20260924T031500Z`.
  private static let releaseStampFormat = Date.ISO8601FormatStyle(
    dateSeparator: .omitted,
    timeSeparator: .omitted
  )

  /// Magic bytes identifying the SRTM binary format: "SRTM" in ASCII.
  private static let magic: [UInt8] = [0x53, 0x52, 0x54, 0x4D]

  /// File format version (3 = per-tile LZFSE compression).
  private static let formatVersion: UInt16 = 3

  /// Name the manifest is written and published under.
  private static let manifestFilename = TerrainManifest.defaultManifestURL.lastPathComponent

  // MARK: - Instance Properties

  /// The terrain regions to process.
  let regions: [TerrainRegion]

  /// Directory where output files will be written.
  let outputLocation: URL

  /// Logger for status messages and errors.
  let logger: Logger

  /// Whether to skip uploading to R2.
  private(set) var skipUpload: Bool = false

  // MARK: - Callbacks

  /// Callback invoked when progress state changes.
  var onProgress: (@MainActor @Sendable (TerrainProgress) -> Void)?

  /// Callback invoked if R2 upload fails.
  var onUploadError: (@MainActor @Sendable (any Error) -> Void)?

  /// Callback invoked for each log entry.
  var onLog: (@MainActor @Sendable (LogEntry) -> Void)?

  private let byteCountFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter
  }()

  private let iso8601Formatter = ISO8601DateFormatter()

  /// URL session for downloads (cached to avoid creating new sessions per request).
  private let urlSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 60
    config.timeoutIntervalForResource = 600
    return URLSession(configuration: config)
  }()

  /// Public URL of the bucket everything is published to.
  private var publicRoot: String {
    R2Uploader.Config.fromBundle()?.publicURL
      ?? TerrainManifest.defaultBaseURL.deletingLastPathComponent().absoluteString
  }

  // MARK: - Initializers

  init(regions: [TerrainRegion], outputLocation: URL, logger: Logger) {
    self.regions = regions
    self.outputLocation = outputLocation
    self.logger = logger
  }

  // MARK: - Type Methods

  /// Fetches one tile, reads it onto the output grid and compresses it with LZFSE.
  ///
  /// This is a static (non-isolated) function to enable true parallelism in TaskGroup.
  ///
  /// - Throws: ``SRTMProcessorError`` if the tile cannot be downloaded. A tile that downloads but
  ///   cannot be read comes back carrying its error instead, so the region reports every such
  ///   tile before it fails.
  private static func fetchAndCompressTile(
    _ tile: TileCoordinates,
    from source: TileSource,
    index: Int,
    into directory: URL,
    using session: URLSession
  ) async throws -> CompressedTile {
    let content: TileContent
    switch source {
      case .copernicus(let url):
        content = .geoTIFF(try await download(url, into: directory, using: session))
      case .openSea:
        content = .seaLevel
    }
    defer {
      if case .geoTIFF(let fileURL) = content {
        try? FileManager.default.removeItem(at: fileURL)
      }
    }

    let parsed = TileProcessing.parseTile(
      TileReference(content: content, coordinates: tile),
      index: index,
      samplesPerSide: samplesPerSide
    )
    return compress(parsed, isSeaLevel: source.isOpenSea)
  }

  /// Downloads `url` into `directory`, retrying failures before giving up on the region.
  private static func download(
    _ url: URL,
    into directory: URL,
    using session: URLSession
  ) async throws -> URL {
    let tileName = url.lastPathComponent
    var lastError: any Error = SRTMProcessorError.unexpectedStatus(tile: tileName, statusCode: nil)

    for attempt in 1...maxDownloadAttempts {
      do {
        let (downloadedURL, response) = try await session.download(from: url)
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        guard statusCode == 200 else {
          try? FileManager.default.removeItem(at: downloadedURL)
          throw SRTMProcessorError.unexpectedStatus(tile: tileName, statusCode: statusCode)
        }
        let destination = directory.appending(component: tileName)
        try FileManager.default.moveItem(at: downloadedURL, to: destination)
        return destination
      } catch {
        lastError = error
        try Task.checkCancellation()
        if attempt < maxDownloadAttempts {
          try await Task.sleep(for: downloadRetryDelay * attempt)
        }
      }
    }

    throw SRTMProcessorError.downloadFailed(tile: tileName, error: lastError)
  }

  /// Compresses a parsed tile's elevations with LZFSE, or carries its parse error forward.
  private static func compress(_ parsed: ParsedTile, isSeaLevel: Bool) -> CompressedTile {
    guard let elevations = parsed.elevations else {
      return CompressedTile(
        index: parsed.index,
        coordinates: parsed.coordinates,
        payload: .failed,
        error: parsed.error
      )
    }

    if elevations.isAllVoid {
      return CompressedTile(
        index: parsed.index,
        coordinates: parsed.coordinates,
        payload: .void,
        error: nil
      )
    }

    let rawData = elevations.littleEndianData
    do {
      // swiftlint:disable:next legacy_objc_type
      let compressedData = try (rawData as NSData).compressed(using: .lzfse) as Data
      return CompressedTile(
        index: parsed.index,
        coordinates: parsed.coordinates,
        payload: .data(
          compressedData,
          uncompressedLength: UInt32(rawData.count),
          isSeaLevel: isSeaLevel
        ),
        error: nil
      )
    } catch {
      return CompressedTile(
        index: parsed.index,
        coordinates: parsed.coordinates,
        payload: .failed,
        error: SRTMProcessorError.compressionFailed(error)
      )
    }
  }

  // MARK: - Methods

  /// Sets whether to skip R2 upload.
  func setSkipUpload(_ value: Bool) {
    skipUpload = value
  }

  /// Sets all callback handlers at once.
  func setCallbacks(
    onProgress: (@MainActor @Sendable (TerrainProgress) -> Void)?,
    onUploadError: (@MainActor @Sendable (any Error) -> Void)?,
    onLog: (@MainActor @Sendable (LogEntry) -> Void)?
  ) {
    self.onProgress = onProgress
    self.onUploadError = onUploadError
    self.onLog = onLog
  }

  // MARK: - Progress Reporting

  /// Reports progress state via callback.
  private func reportProgress(_ state: TerrainProgress) async {
    if let onProgress {
      await onProgress(state)
    }
  }

  /// Reports a log entry via callback and logger.
  private func reportLog(level: Logger.Level, message: String) async {
    logger.log(level: level, "\(message)")
    if let onLog {
      let entry = LogEntry(
        timestamp: Date(),
        level: level,
        message: message,
        metadata: nil
      )
      await onLog(entry)
    }
  }

  // MARK: - Main Processing Pipeline

  /// Executes the complete terrain data processing pipeline.
  func process() async throws {
    await reportLog(
      level: .notice,
      message: "Starting SRTM terrain processing for \(regions.count) region(s)"
    )
    await reportProgress(.pending)

    if !regions.isEmpty {
      let catalog = try await CopernicusTileCatalog.load(using: urlSession)
      for region in regions {
        try Task.checkCancellation()
        try await processRegion(region, catalog: catalog)
      }
    }

    try Task.checkCancellation()

    // Generate manifest
    await reportProgress(.generatingManifest)
    await reportLog(level: .notice, message: "Generating manifest…")
    try await generateManifest()

    try Task.checkCancellation()

    let assetPacks = try await packageAssetPacks()

    try Task.checkCancellation()

    try await uploadToR2Storage(assetPacks: assetPacks)

    await reportProgress(.completed)
    await reportLog(
      level: .notice,
      message: "Complete - processed \(regions.count) terrain region(s)"
    )
  }

  /// Cancels the processing.
  func cancel() async {
    await reportProgress(.cancelled)
    await reportLog(level: .warning, message: "Terrain processing cancelled by user")
  }

  // MARK: - Region Processing

  /// Processes a single terrain region into its payload in the output directory.
  private func processRegion(_ region: TerrainRegion, catalog: CopernicusTileCatalog) async throws {
    await reportLog(level: .notice, message: "Processing \(region.displayName)…")

    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("srtm-\(region.rawValue)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    try await buildPayload(
      for: region,
      tiles: region.tileCoordinates,
      catalog: catalog,
      scratchDirectory: tempDir
    )
  }

  /// Writes the region's payload: a header, a tile index, then each tile LZFSE-compressed.
  ///
  /// Every tile in the region's bounding boxes is written, open sea included, so the payload has
  /// an answer for every point it covers.
  private func buildPayload(
    for region: TerrainRegion,
    tiles: [TileCoordinates],
    catalog: CopernicusTileCatalog,
    scratchDirectory: URL
  ) async throws {
    let total = tiles.count
    await reportLog(level: .notice, message: "Building \(total) tiles for \(region.displayName)…")
    await reportProgress(.building(region: region, completed: 0, total: total))

    let boundingBox = region.overallBoundingBox

    // Build header: magic (4) + version (2) + resolution (2) + tileCount (4) + boundingBox (8)
    var headerData = Data(Self.magic)
    headerData.append(Self.formatVersion, .littleEndian)
    headerData.append(UInt16(Self.samplesPerSide), .littleEndian)  // Resolution
    headerData.append(UInt32(total), .littleEndian)  // Tile count
    for bound in [boundingBox.minLat, boundingBox.maxLat, boundingBox.minLon, boundingBox.maxLon] {
      headerData.append(Int16(bound), .littleEndian)  // Bounding box
    }

    // Version 3 format: lat(2) + lon(2) + offset(8) + compressedLength(4) + uncompressedLength(4) = 20 bytes
    let tileIndexEntrySize = 20
    let tileIndexSize = total * tileIndexEntrySize
    let dataStartOffset = UInt64(headerData.count + tileIndexSize)

    // Write to a temporary file to avoid holding everything in memory
    let tempOutputFile = outputLocation.appendingPathComponent("\(region.rawValue)-temp.srtm")
    FileManager.default.createFile(atPath: tempOutputFile.path, contents: nil)
    let fileHandle = try FileHandle(forWritingTo: tempOutputFile)

    defer {
      try? fileHandle.close()
    }

    // Write header + placeholder index (will be overwritten after compression)
    try fileHandle.write(contentsOf: headerData)
    try fileHandle.write(contentsOf: Data(count: tileIndexSize))

    let result = try await fetchCompressAndWriteTiles(
      tiles,
      region: region,
      catalog: catalog,
      scratchDirectory: scratchDirectory,
      dataStartOffset: dataStartOffset,
      fileHandle: fileHandle
    )

    // Seek back and write the actual tile index
    try fileHandle.seek(toOffset: UInt64(headerData.count))
    var tileIndex = Data()
    for entry in result.indexEntries {
      tileIndex.append(Int16(entry.coordinates.latitude), .littleEndian)
      tileIndex.append(Int16(entry.coordinates.longitude), .littleEndian)
      tileIndex.append(entry.dataOffset, .littleEndian)
      tileIndex.append(entry.compressedLength, .littleEndian)
      tileIndex.append(entry.uncompressedLength, .littleEndian)
    }
    try fileHandle.write(contentsOf: tileIndex)

    let stats = result.stats
    await reportLog(
      level: .info,
      message: """
        LZFSE compression for \(region.displayName): \(stats.seaLevelTiles) open-sea tiles, \
        \(stats.voidTiles) void tiles, \
        \(byteCountFormatter.string(fromByteCount: Int64(stats.totalUncompressedBytes))) → \
        \(byteCountFormatter.string(fromByteCount: Int64(stats.totalCompressedBytes))) \
        (\(stats.compressionRatio.formatted(.percent.precision(.fractionLength(1))))))
        """
    )

    try fileHandle.synchronize()
    try fileHandle.close()

    // Every tile in the payload is already LZFSE-compressed, so the file is published as it stands.
    let payloadFile = outputLocation.appendingPathComponent(region.remoteFilename)
    if FileManager.default.fileExists(atPath: payloadFile.path) {
      try FileManager.default.removeItem(at: payloadFile)
    }
    try FileManager.default.moveItem(at: tempOutputFile, to: payloadFile)

    let payloadSize =
      try FileManager.default.attributesOfItem(atPath: payloadFile.path)[.size]
      as? Int ?? 0
    await reportLog(
      level: .notice,
      message: """
        Wrote \(region.displayName): \(byteCountFormatter.string(fromByteCount: Int64(payloadSize)))
        """
    )
  }

  /// Fetches, parses and LZFSE-compresses tiles in parallel, and writes them sequentially in
  /// order.
  ///
  /// Each tile's GeoTIFF is deleted as soon as it is compressed, so the scratch directory never
  /// holds more than the tiles in flight. Returns the tile index entries (with compressed sizes)
  /// and compression statistics.
  ///
  /// - Throws: ``SRTMProcessorError/tilesFailed(region:count:)`` if any tile could not be read.
  ///   A region with a hole in it is not published.
  private func fetchCompressAndWriteTiles(
    _ tiles: [TileCoordinates],
    region: TerrainRegion,
    catalog: CopernicusTileCatalog,
    scratchDirectory: URL,
    dataStartOffset: UInt64,
    fileHandle: FileHandle
  ) async throws -> CompressedWriteResult {
    var writer = TileWriter(fileHandle: fileHandle, dataOffset: dataStartOffset)
    var buffer: [Int: CompressedTile] = [:]
    let session = urlSession

    try await withThrowingTaskGroup(of: CompressedTile.self) { group in
      var nextToStart = 0

      func startNextTile() {
        guard nextToStart < tiles.count else { return }
        let index = nextToStart,
          tile = tiles[index],
          source = catalog.source(for: tile)
        group.addTask {
          try await Self.fetchAndCompressTile(
            tile,
            from: source,
            index: index,
            into: scratchDirectory,
            using: session
          )
        }
        nextToStart += 1
      }

      for _ in 0..<Self.maxConcurrentTiles { startNextTile() }

      for try await result in group {
        buffer[result.index] = result

        // Write any consecutive ready tiles to maintain file order
        while let tile = buffer.removeValue(forKey: writer.indexEntries.count) {
          if let error = tile.error {
            await reportLog(
              level: .error,
              message:
                "Failed to read tile \(tile.coordinates.copernicusName): \(error.localizedDescription)"
            )
          }
          try writer.write(tile)
        }

        await reportProgress(
          .building(region: region, completed: writer.indexEntries.count, total: tiles.count)
        )
        try Task.checkCancellation()
        startNextTile()
      }
    }

    guard writer.stats.failedTiles == 0 else {
      throw SRTMProcessorError.tilesFailed(
        region: region.displayName,
        count: writer.stats.failedTiles
      )
    }
    return CompressedWriteResult(indexEntries: writer.indexEntries, stats: writer.stats)
  }

  // MARK: - Manifest Generation

  /// Generates the terrain manifest JSON file.
  ///
  /// Validates that ALL regions have payloads in the output directory (not just the regions
  /// processed in this run). This allows partial processing when pre-existing `.srtm` files are
  /// copied to the output directory before running.
  private func generateManifest() async throws {
    // Validate that all regions have payloads in the output directory
    var missingRegions: [TerrainRegion] = []
    var allRegionData: [(region: TerrainRegion, fileURL: URL, sizeBytes: Int)] = []

    for region in TerrainRegion.allCases {
      let payloadFile = outputLocation.appendingPathComponent(region.remoteFilename)

      if let attrs = try? FileManager.default.attributesOfItem(atPath: payloadFile.path),
        let size = attrs[.size] as? Int
      {
        allRegionData.append((region: region, fileURL: payloadFile, sizeBytes: size))
      } else {
        missingRegions.append(region)
      }
    }

    // If any regions are missing, throw an error listing them
    if !missingRegions.isEmpty {
      await reportLog(
        level: .error,
        message:
          "Missing compressed files for \(missingRegions.count) region(s): \(missingRegions.map(\.displayName).joined(separator: ", "))"
      )
      throw SRTMProcessorError.missingRegions(missingRegions)
    }

    // Get base URL from R2 config
    let baseURL: String?
    if let config = R2Uploader.Config.fromBundle(), !config.publicURL.isEmpty {
      let url =
        config.publicURL.hasSuffix("/")
        ? config.publicURL + "terrain/"
        : config.publicURL + "/terrain/"
      // Validate URL format
      if URL(string: url) != nil {
        baseURL = url
      } else {
        baseURL = nil
        await reportLog(level: .warning, message: "R2 public URL is malformed: \(config.publicURL)")
      }
    } else {
      baseURL = nil
      await reportLog(
        level: .warning,
        message: "R2 not configured, manifest will not include baseURL"
      )
    }

    var manifest: [String: Any] = [
      "version": TerrainManifest.currentVersion,
      "generatedAt": iso8601Formatter.string(from: Date())
    ]

    if let baseURL {
      manifest["baseURL"] = baseURL
    }

    // Build regions array from all found files (not just processed ones)
    manifest["regions"] = allRegionData.map { data -> [String: Any] in
      [
        "id": data.region.rawValue,
        "filename": data.region.remoteFilename,
        "sizeBytes": data.sizeBytes
      ]
    }

    let jsonData = try JSONSerialization.data(
      withJSONObject: manifest,
      options: [.prettyPrinted, .sortedKeys]
    )

    let manifestFile = outputLocation.appendingPathComponent(Self.manifestFilename)
    try jsonData.write(to: manifestFile)

    await reportLog(
      level: .notice,
      message: "Generated \(Self.manifestFilename) with \(allRegionData.count) regions"
    )
  }

  // MARK: - Asset-Pack Packaging

  /// Packages every region as an asset pack and writes the download manifest indexing them.
  ///
  /// Packaging covers all regions rather than just the ones processed in this run, for the same
  /// reason ``generateManifest(for:)`` does: the download manifest names every pack a device may
  /// ask for, so a partial run must still publish a complete index.
  private func packageAssetPacks() async throws -> AssetPacks {
    let publisher = AssetPackPublisher(
      outputLocation: outputLocation,
      logger: logger,
      publicRoot: publicRoot,
      releaseStamp: Date.now.formatted(Self.releaseStampFormat)
    )

    var packaged: [AssetPackPublisher.PackagedRegion] = []
    for region in TerrainRegion.allCases {
      try Task.checkCancellation()
      await reportProgress(.packaging(region: region))
      packaged.append(try await publisher.packageRegion(region))
    }

    let manifestURL = try await publisher.writeDownloadManifest(for: packaged)
    let rebuiltCount = packaged.count(where: \.isRebuilt)
    await reportLog(
      level: .notice,
      message: """
        Packaged \(packaged.count) asset packs (\(rebuiltCount) rebuilt) against \
        \(publisher.downloadBaseURL)
        """
    )

    return .init(publisher: publisher, packaged: packaged, downloadManifest: manifestURL)
  }

  // MARK: - R2 Upload

  /// Uploads the payloads, the asset packs and the manifests indexing them to CloudFlare R2.
  ///
  /// Each manifest goes up only after everything it names is in place, and a failed upload stops
  /// the run before any manifest does, so no device is ever pointed at a file the bucket cannot
  /// serve. The download manifest goes last: publishing it is what releases the packs to devices.
  private func uploadToR2Storage(assetPacks: AssetPacks) async throws {
    if skipUpload {
      await reportLog(level: .info, message: "Skipping R2 upload (skipUpload=true)")
      return
    }

    guard let config = R2Uploader.Config.fromBundle() else {
      await reportLog(level: .info, message: "R2 not configured, skipping upload")
      return
    }

    await reportLog(level: .notice, message: "Uploading to R2…")
    let uploader = R2Uploader(config: config, logger: logger)

    do {
      try await uploadPayloads(using: uploader)
      try await uploadFile(
        outputLocation.appendingPathComponent(Self.manifestFilename),
        key: "terrain/" + Self.manifestFilename,
        using: uploader
      )
      try await uploadAssetPacks(assetPacks, publicRoot: config.publicURL, using: uploader)
      await reportLog(level: .notice, message: "Successfully uploaded terrain data to R2")
    } catch {
      await reportLog(level: .error, message: "R2 upload failed: \(error.localizedDescription)")
      if let onUploadError {
        await onUploadError(error)
      }
      throw error
    }
  }

  /// Uploads each region's payload for the builds that download payloads directly, skipping any
  /// the bucket already holds at the same size.
  private func uploadPayloads(using uploader: R2Uploader) async throws {
    for region in TerrainRegion.allCases {
      let payloadURL = outputLocation.appendingPathComponent(region.remoteFilename),
        key = "terrain/\(region.remoteFilename)"
      let localSize =
        try FileManager.default.attributesOfItem(atPath: payloadURL.path)[.size]
        as? Int64
      guard try await uploader.publishedSize(ofObjectAt: key) != localSize else {
        await reportLog(level: .info, message: "\(key) is already published")
        continue
      }
      try await uploadFile(payloadURL, key: key, region: region, using: uploader)
    }
  }

  /// Uploads each asset-pack archive under the key its download-manifest URL names, then the
  /// download manifest.
  ///
  /// A published archive is never overwritten: a device may be part-way through downloading it.
  /// An archive whose key is already occupied is the one published there before.
  private func uploadAssetPacks(
    _ assetPacks: AssetPacks,
    publicRoot: String,
    using uploader: R2Uploader
  ) async throws {
    let keys = try assetPacks.publisher.publishedKeys(
      inManifestAt: assetPacks.downloadManifest,
      publicRoot: publicRoot
    )

    for pack in assetPacks.packaged {
      guard let key = keys[pack.region] else {
        throw AssetPackPublisherError.packMissingFromManifest(region: pack.region)
      }
      guard try await uploader.publishedSize(ofObjectAt: key) == nil else {
        await reportLog(level: .info, message: "\(key) is already published")
        continue
      }
      try await uploadFile(pack.archiveURL, key: key, region: pack.region, using: uploader)
    }

    await reportProgress(.uploadingManifest)
    try await uploadFile(
      assetPacks.downloadManifest,
      key: AssetPackPublisher.downloadManifestFilename,
      using: uploader
    )
  }

  /// Uploads one file, reporting progress against `region` when it belongs to one.
  private func uploadFile(
    _ fileURL: URL,
    key: String,
    region: TerrainRegion? = nil,
    using uploader: R2Uploader
  ) async throws {
    guard let region else {
      await reportProgress(.uploadingManifest)
      try await uploader.uploadFile(at: fileURL, key: key)
      return
    }
    await reportProgress(.uploading(region: region, fraction: 0.0))
    try await uploader.uploadFile(at: fileURL, key: key) { fraction in
      await self.reportProgress(.uploading(region: region, fraction: fraction))
    }
  }

  // MARK: - Nested Types

  /// The packaged asset packs and the download manifest indexing them.
  private struct AssetPacks {
    let publisher: AssetPackPublisher
    let packaged: [AssetPackPublisher.PackagedRegion]
    let downloadManifest: URL
  }

  /// Result of a single tile's fetch-parse-compress operation.
  private struct CompressedTile: Sendable {
    let index: Int
    let coordinates: TileCoordinates
    let payload: Payload
    let error: (any Error)?

    enum Payload: Sendable {
      /// LZFSE-compressed elevations.
      case data(Data, uncompressedLength: UInt32, isSeaLevel: Bool)
      /// Every sample is void; stored with no data.
      case void
      /// The tile could not be read or compressed.
      case failed
    }
  }

  /// Tile index information for a single compressed tile.
  private struct TileIndexInfo {
    let coordinates: TileCoordinates
    let dataOffset: UInt64
    let compressedLength: UInt32
    let uncompressedLength: UInt32
  }

  /// Appends tiles to a payload in order, recording each one's index entry.
  private struct TileWriter {
    let fileHandle: FileHandle
    var dataOffset: UInt64
    private(set) var indexEntries: [TileIndexInfo] = []
    private(set) var stats = CompressionStats()

    init(fileHandle: FileHandle, dataOffset: UInt64) {
      self.fileHandle = fileHandle
      self.dataOffset = dataOffset
    }

    /// Writes `tile`'s data, if any, and records where it landed. A void or failed tile is
    /// indexed with zero lengths.
    mutating func write(_ tile: CompressedTile) throws {
      var compressedLength: UInt32 = 0,
        uncompressedLength: UInt32 = 0

      switch tile.payload {
        case let .data(data, length, isSeaLevel):
          try fileHandle.write(contentsOf: data)
          compressedLength = UInt32(data.count)
          uncompressedLength = length
          stats.totalCompressedBytes += data.count
          stats.totalUncompressedBytes += Int(length)
          if isSeaLevel { stats.seaLevelTiles += 1 }
        case .void:
          stats.voidTiles += 1
        case .failed:
          stats.failedTiles += 1
      }

      indexEntries.append(
        TileIndexInfo(
          coordinates: tile.coordinates,
          dataOffset: dataOffset,
          compressedLength: compressedLength,
          uncompressedLength: uncompressedLength
        )
      )
      dataOffset += UInt64(compressedLength)
    }
  }

  /// Result of the parse-compress-write pipeline for all tiles in a region.
  private struct CompressedWriteResult {
    let indexEntries: [TileIndexInfo]
    let stats: CompressionStats
  }

  /// Statistics about per-tile LZFSE compression for a region.
  private struct CompressionStats {
    var seaLevelTiles: Int = 0
    var voidTiles: Int = 0
    var failedTiles: Int = 0
    var totalUncompressedBytes: Int = 0
    var totalCompressedBytes: Int = 0

    var compressionRatio: Double {
      guard totalUncompressedBytes > 0 else { return 0 }
      return Double(totalCompressedBytes) / Double(totalUncompressedBytes)
    }
  }
}
