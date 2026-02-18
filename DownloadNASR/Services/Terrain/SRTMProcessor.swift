import Compression
import Foundation
import Logging
import SF50_Shared
import StreamingLZMA

/// Errors that can occur during SRTM processing.
enum SRTMProcessorError: LocalizedError {
  case noTilesFound(region: String)
  case downloadFailed(tile: String, error: Error)
  case compressionFailed(Error)
  case missingRegions([TerrainRegion])

  var errorDescription: String? {
    String(localized: "Terrain processing failed.")
  }

  var failureReason: String? {
    switch self {
      case .noTilesFound(let region):
        return String(localized: "No SRTM tiles were found for region \(region).")
      case .downloadFailed(let tile, let error):
        return String(localized: "Failed to download tile “\(tile)”: \(error.localizedDescription)")
      case .compressionFailed(let error):
        return String(localized: "Failed to compress terrain data: \(error.localizedDescription)")
      case .missingRegions(let regions):
        let names = regions.map(\.displayName)
        return String(
          localized:
            "Cannot generate manifest: Missing compressed files for regions: \(names, format: .list(type: .and)). Copy existing .lzma files to the output directory or select these regions for processing."
        )
    }
  }
}

/// Orchestrates the complete SRTM terrain data processing pipeline.
///
/// ``SRTMProcessor`` coordinates the downloading, parsing, and output of SRTM data:
///
/// 1. Download HGT tiles for selected regions
/// 2. Parse elevation data from HGT files
/// 3. Combine into optimized binary format per continent
/// 4. Compress using LZMA
/// 5. Generate terrain manifest
/// 6. Upload to CloudFlare R2 (if configured)
///
/// ## Data Source
///
/// Uses AWS Terrain Tiles (elevation-tiles-prod.s3.amazonaws.com) which provides
/// public access to SRTM1 data (1 arc-second / ~30m resolution).
///
/// ## Progress Tracking
///
/// The processor uses callbacks to report progress:
/// - `onProgress`: Called when progress state changes
/// - `onUploadError`: Called if R2 upload fails
/// - `onLog`: Called for each log entry
actor SRTMProcessor {

  // MARK: - Type Properties

  /// Maximum concurrent downloads (AWS S3 handles high concurrency well).
  private static let maxConcurrentDownloads = 20

  /// Maximum concurrent parsing tasks (limits memory usage).
  private static let maxConcurrentParsing = 8

  /// Base URL for AWS Terrain Tiles (SRTM1 data).
  private static let awsBaseURL = "https://elevation-tiles-prod.s3.amazonaws.com/skadi"

  /// Base URL for Copernicus GLO-30 DEM data.
  private static let copernicusBaseURL = "https://copernicus-dem-30m.s3.amazonaws.com"

  /// Magic bytes identifying the SRTM binary format: "SRTM" in ASCII.
  private static let magic: [UInt8] = [0x53, 0x52, 0x54, 0x4D]

  /// File format version (3 = per-tile LZFSE compression).
  private static let formatVersion: UInt16 = 3

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
  var onUploadError: (@MainActor @Sendable (Error) -> Void)?

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

  // MARK: - Initializers

  init(regions: [TerrainRegion], outputLocation: URL, logger: Logger) {
    self.regions = regions
    self.outputLocation = outputLocation
    self.logger = logger
  }

  // MARK: - Type Methods

  /// Parses a tile and compresses its elevation data with LZFSE.
  ///
  /// This is a static (non-isolated) function to enable true parallelism in TaskGroup.
  private static func parseAndCompressTile(
    _ tileRef: TileReference,
    index: Int,
    outputResolution: HGTParser.Resolution
  ) -> CompressedTile {
    let parsed = TileProcessing.parseTile(tileRef, index: index, outputResolution: outputResolution)

    guard let elevations = parsed.elevations else {
      return CompressedTile(
        index: index,
        latitude: parsed.latitude,
        longitude: parsed.longitude,
        compressedData: nil,
        uncompressedLength: 0,
        isVoid: false,
        error: parsed.error
      )
    }

    // Check for all-void tile (ocean)
    let isAllVoid = elevations.withUnsafeBufferPointer { buffer in
      buffer.allSatisfy { $0 == Elevations.voidValue }
    }

    if isAllVoid {
      return CompressedTile(
        index: index,
        latitude: parsed.latitude,
        longitude: parsed.longitude,
        compressedData: nil,
        uncompressedLength: 0,
        isVoid: true,
        error: nil
      )
    }

    // Serialize elevation data to raw bytes
    let rawData = elevations.withUnsafeBufferPointer { buffer in
      Data(buffer: buffer)
    }
    let uncompressedLength = UInt32(rawData.count)

    // Compress with LZFSE
    guard let compressedData = compressWithLZFSE(rawData) else {
      return CompressedTile(
        index: index,
        latitude: parsed.latitude,
        longitude: parsed.longitude,
        compressedData: nil,
        uncompressedLength: 0,
        isVoid: false,
        error: SRTMProcessorError.compressionFailed(
          NSError(
            domain: "LZFSE",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "LZFSE compression returned 0 bytes"]
          )
        )
      )
    }

    return CompressedTile(
      index: index,
      latitude: parsed.latitude,
      longitude: parsed.longitude,
      compressedData: compressedData,
      uncompressedLength: uncompressedLength,
      isVoid: false,
      error: nil
    )
  }

  /// Compresses data using LZFSE.
  private static func compressWithLZFSE(_ data: Data) -> Data? {
    let srcSize = data.count
    var dstBuffer = [UInt8](repeating: 0, count: srcSize)

    let compressedSize = data.withUnsafeBytes { srcBuffer -> Int in
      guard let srcPointer = srcBuffer.baseAddress else { return 0 }
      return compression_encode_buffer(
        &dstBuffer,
        srcSize,
        srcPointer.assumingMemoryBound(to: UInt8.self),
        srcSize,
        nil,
        COMPRESSION_LZFSE
      )
    }

    // If output wouldn't fit in source-sized buffer, retry with a larger one
    if compressedSize == 0 {
      let largerSize = srcSize * 2
      dstBuffer = [UInt8](repeating: 0, count: largerSize)
      let retrySize = data.withUnsafeBytes { srcBuffer -> Int in
        guard let srcPointer = srcBuffer.baseAddress else { return 0 }
        return compression_encode_buffer(
          &dstBuffer,
          largerSize,
          srcPointer.assumingMemoryBound(to: UInt8.self),
          srcSize,
          nil,
          COMPRESSION_LZFSE
        )
      }
      guard retrySize > 0 else { return nil }
      return Data(dstBuffer.prefix(retrySize))
    }

    return Data(dstBuffer.prefix(compressedSize))
  }

  // MARK: - Methods

  /// Sets whether to skip R2 upload.
  func setSkipUpload(_ value: Bool) {
    skipUpload = value
  }

  /// Sets all callback handlers at once.
  func setCallbacks(
    onProgress: (@MainActor @Sendable (TerrainProgress) -> Void)?,
    onUploadError: (@MainActor @Sendable (Error) -> Void)?,
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

    var processedRegions: [ProcessedRegion] = []

    for region in regions {
      try Task.checkCancellation()

      let regionResult = try await processRegion(region)
      processedRegions.append(regionResult)
    }

    try Task.checkCancellation()

    // Generate manifest
    await reportProgress(.generatingManifest)
    await reportLog(level: .notice, message: "Generating manifest…")
    try await generateManifest(for: processedRegions)

    try Task.checkCancellation()

    // Upload to R2
    await uploadToR2Storage(processedRegions: processedRegions)

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

  /// Processes a single terrain region.
  private func processRegion(_ region: TerrainRegion) async throws -> ProcessedRegion {
    await reportLog(level: .notice, message: "Processing \(region.displayName)…")

    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("srtm-\(region.rawValue)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    // Download tiles
    let tiles = try await downloadTiles(for: region, to: tempDir)

    try Task.checkCancellation()

    // Combine and compress
    let outputFile = try await combineAndCompress(tiles: tiles, region: region)

    return ProcessedRegion(
      region: region,
      outputFile: outputFile,
      tileCount: tiles.count
    )
  }

  /// Downloads all SRTM tiles for a region using parallel downloads.
  ///
  /// Uses a throttled `TaskGroup` to download up to ``maxConcurrentDownloads`` tiles simultaneously,
  /// providing 4-5x speedup over sequential downloads while respecting server rate limits.
  /// Returns tile references (not parsed data) to minimize memory usage.
  private func downloadTiles(
    for region: TerrainRegion,
    to directory: URL
  ) async throws -> [TileReference] {
    let tileNames = region.hgtTileNames,
      total = tileNames.count
    await reportLog(level: .notice, message: "Downloading \(total) tiles for \(region.displayName)")
    await reportProgress(.downloading(region: region, completed: 0, total: total))

    return try await withThrowingTaskGroup(of: TileReference?.self) { group in
      var tiles: [TileReference] = []
      var index = 0
      var completed = 0
      var skipped = 0

      // Seed initial batch of concurrent downloads
      while index < min(Self.maxConcurrentDownloads, tileNames.count) {
        let tileName = tileNames[index]
        group.addTask {
          // Download tile, return nil on failure (don't log inside task)
          try? await self.downloadTile(name: tileName, to: directory)
        }
        index += 1
      }

      // Process results as they complete and add new tasks
      for try await result in group {
        completed += 1

        if let tile = result {
          tiles.append(tile)
        } else {
          skipped += 1
        }

        // Report progress
        await reportProgress(.downloading(region: region, completed: completed, total: total))
        try Task.checkCancellation()

        // Add next task if more tiles remain
        if index < tileNames.count {
          let tileName = tileNames[index]
          group.addTask {
            // Download tile, return nil on failure (don't log inside task)
            try? await self.downloadTile(name: tileName, to: directory)
          }
          index += 1
        }
      }

      await reportLog(
        level: .info,
        message: "Downloaded \(tiles.count) tiles, skipped \(skipped) for \(region.displayName)"
      )

      return tiles
    }
  }

  /// Downloads a single terrain tile and returns a reference (not parsed data).
  /// Supports both SRTM HGT files and Copernicus GeoTIFF files.
  /// - Returns: Tile reference, or nil if the tile doesn't exist (water/void)
  private func downloadTile(name: String, to directory: URL) async throws -> TileReference? {
    // Try multiple sources
    let sources = buildDownloadURLs(for: name)

    for sourceURL in sources {
      do {
        let (data, response) = try await urlSession.data(from: sourceURL)

        guard let httpResponse = response as? HTTPURLResponse else {
          continue
        }

        guard httpResponse.statusCode == 200 else {
          if httpResponse.statusCode != 404 {
            logger.error("Source returned \(httpResponse.statusCode) for \(name)")
          }
          continue
        }

        // Determine file format and filename from URL
        let format: TileFormat = sourceURL.pathExtension == "tif" ? .geoTIFF : .hgt
        let filename =
          switch format {
            case .geoTIFF:
              // Use original Copernicus filename (needed for coordinate parsing)
              sourceURL.lastPathComponent
            case .hgt:
              sourceURL.pathExtension == "gz" ? "\(name).hgt.gz" : "\(name).hgt.zip"
          }

        let localURL = directory.appendingPathComponent(filename)
        try data.write(to: localURL)

        // Extract coordinates from tile name (e.g., "N45W123")
        let coords = try HGTParser.parseCoordinates(from: name)

        return TileReference(
          fileURL: localURL,
          latitude: coords.latitude,
          longitude: coords.longitude,
          format: format
        )
      } catch {
        // Try next source
        continue
      }
    }

    // No source had this tile - it's likely a water/void area
    return nil
  }

  /// Builds download URLs for a tile from available sources.
  ///
  /// Uses a hybrid source strategy:
  /// - SRTM (60°N to 56°S): AWS Terrain Tiles (primary source)
  /// - Copernicus GLO-30 (84°N to 85°S): Fallback for extreme latitudes
  private func buildDownloadURLs(for tileName: String) -> [URL] {
    var urls: [URL] = []

    // Parse tile coordinates
    guard let coords = try? HGTParser.parseCoordinates(from: tileName) else {
      return []
    }

    let uppercased = tileName.uppercased()

    // Extract latitude folder for AWS path (e.g., "N45" or "S35")
    var latNumEndIndex = uppercased.index(uppercased.startIndex, offsetBy: 1)
    for char in uppercased.dropFirst() {
      if char == "E" || char == "W" {
        break
      }
      latNumEndIndex = uppercased.index(after: latNumEndIndex)
    }
    let latFolder = String(uppercased[..<latNumEndIndex])  // e.g., "N45" or "S35"

    // SRTM coverage: 60°N to 56°S
    let inSRTMCoverage = coords.latitude >= -56 && coords.latitude < 60

    if inSRTMCoverage {
      // AWS Terrain Tiles (public, SRTM1 resolution) - primary source
      // Format: https://elevation-tiles-prod.s3.amazonaws.com/skadi/{lat_folder}/{tileName}.hgt.gz
      guard let url = URL(string: "\(Self.awsBaseURL)/\(latFolder)/\(uppercased).hgt.gz") else {
        fatalError("Failed to construct AWS URL for tile \(tileName)")
      }
      urls.append(url)
    }

    // Copernicus GLO-30 (fallback, or primary for extreme latitudes)
    // Coverage: 84°N to 85°S (essentially all airports)
    urls.append(buildCopernicusURL(for: coords))

    return urls
  }

  /// Builds a Copernicus GLO-30 download URL for the given coordinates.
  ///
  /// Copernicus GLO-30 data is available via AWS S3 (no authentication required):
  /// - Bucket: `s3://copernicus-dem-30m/`
  /// - HTTP: `https://copernicus-dem-30m.s3.amazonaws.com/`
  ///
  /// Tile naming convention:
  /// `Copernicus_DSM_COG_10_{N|S}{lat:02d}_00_{E|W}{lon:03d}_00_DEM/Copernicus_DSM_COG_10_{N|S}{lat:02d}_00_{E|W}{lon:03d}_00_DEM.tif`
  private func buildCopernicusURL(for coords: HGTParser.Coordinates) -> URL {
    let ns = coords.latitude >= 0 ? "N" : "S",
      ew = coords.longitude >= 0 ? "E" : "W",
      lat = String(format: "%02d", abs(coords.latitude)),
      lon = String(format: "%03d", abs(coords.longitude))
    let tileName = "Copernicus_DSM_COG_10_\(ns)\(lat)_00_\(ew)\(lon)_00_DEM"
    guard let url = URL(string: "\(Self.copernicusBaseURL)/\(tileName)/\(tileName).tif") else {
      fatalError("Failed to construct Copernicus URL for coordinates \(coords)")
    }
    return url
  }

  /// Combines tiles into a single v3 binary file with per-tile LZFSE compression.
  private func combineAndCompress(
    tiles: [TileReference],
    region: TerrainRegion
  ) async throws -> URL {
    let total = tiles.count
    await reportLog(level: .notice, message: "Combining \(total) tiles for \(region.displayName)…")
    await reportProgress(.parsing(region: region, completed: 0, total: total))

    guard !tiles.isEmpty else {
      throw SRTMProcessorError.noTilesFound(region: region.displayName)
    }

    let boundingBox = region.overallBoundingBox

    // Always output SRTM3 resolution for manageable file sizes
    // SRTM1 (~30m) tiles will be downsampled to SRTM3 (~90m)
    let outputResolution = HGTParser.Resolution.srtm3

    // Build header: magic (4) + version (2) + resolution (2) + tileCount (4) + boundingBox (8)
    let headerData = try BinaryFileWriter.buildData { writer in
      writer.writeBytes(Self.magic)
      writer.writeUInt16(Self.formatVersion)
      writer.writeUInt16(UInt16(outputResolution.samplesPerSide))  // Resolution
      writer.writeUInt32(UInt32(tiles.count))  // Tile count
      writer.writeInt16(Int16(boundingBox.minLat))  // Bounding box
      writer.writeInt16(Int16(boundingBox.maxLat))
      writer.writeInt16(Int16(boundingBox.minLon))
      writer.writeInt16(Int16(boundingBox.maxLon))
    }

    // Version 3 format: lat(2) + lon(2) + offset(8) + compressedLength(4) + uncompressedLength(4) = 20 bytes
    let tileIndexEntrySize = 20
    let tileIndexSize = tiles.count * tileIndexEntrySize
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

    // Parse, compress, and write tiles; returns actual index entries and stats
    let result = try await parseCompressAndWriteTiles(
      tiles: tiles,
      region: region,
      outputResolution: outputResolution,
      dataStartOffset: dataStartOffset,
      fileHandle: fileHandle
    )

    // Seek back and write the actual tile index
    try fileHandle.seek(toOffset: UInt64(headerData.count))
    let tileIndex = try BinaryFileWriter.buildData { writer in
      for entry in result.indexEntries {
        writer.writeInt16(Int16(entry.latitude))
        writer.writeInt16(Int16(entry.longitude))
        writer.writeUInt64(entry.dataOffset)
        writer.writeUInt32(entry.compressedLength)
        writer.writeUInt32(entry.uncompressedLength)
      }
    }
    try fileHandle.write(contentsOf: tileIndex)

    let stats = result.stats
    if stats.failedTiles > 0 {
      await reportLog(
        level: .warning,
        message: "Skipped \(stats.failedTiles) tiles due to parsing errors"
      )
    }

    await reportLog(
      level: .info,
      message: """
        LZFSE compression for \(region.displayName): \(stats.voidTiles) void tiles, \
        \(byteCountFormatter.string(fromByteCount: Int64(stats.totalUncompressedBytes))) → \
        \(byteCountFormatter.string(fromByteCount: Int64(stats.totalCompressedBytes))) \
        (\(String(format: "%.1f%%", stats.compressionRatio * 100)))
        """
    )

    try fileHandle.synchronize()
    try fileHandle.close()

    // Get uncompressed file size
    let uncompressedAttrs = try FileManager.default.attributesOfItem(atPath: tempOutputFile.path)
    let uncompressedSize = uncompressedAttrs[.size] as? Int ?? 0

    // Compress with LZMA using streaming to avoid loading entire file into memory
    await reportProgress(.compressing(region: region, fraction: 0.0))
    await reportLog(level: .notice, message: "Compressing \(region.displayName)…")

    let compressedFile = outputLocation.appendingPathComponent(region.compressedFilename)

    // Open input file for reading
    let inputHandle = try FileHandle(forReadingFrom: tempOutputFile)
    defer { try? inputHandle.close() }

    // Create output file and open for writing
    FileManager.default.createFile(atPath: compressedFile.path, contents: nil)
    let outputHandle = try FileHandle(forWritingTo: compressedFile)
    defer { try? outputHandle.close() }

    // Stream compress with progress reporting (uses ~2 MB with highThroughput config)
    let fileSize = Int64(uncompressedSize)
    let progressCallback = onProgress
    do {
      try inputHandle.lzmaFileCompress(
        to: outputHandle,
        configuration: .highThroughput
      ) { bytesRead in
        let fraction = Double(bytesRead) / Double(fileSize)
        Task { @MainActor in
          progressCallback?(.compressing(region: region, fraction: fraction))
        }
      }
    } catch {
      throw SRTMProcessorError.compressionFailed(error)
    }

    await reportProgress(.compressing(region: region, fraction: 1.0))
    try Task.checkCancellation()

    try inputHandle.close()
    try outputHandle.close()

    // Delete temp file to save disk space (only keep compressed version)
    try FileManager.default.removeItem(at: tempOutputFile)

    // Get compressed file size for logging
    let compressedAttrs = try FileManager.default.attributesOfItem(atPath: compressedFile.path)
    let compressedSize = compressedAttrs[.size] as? Int ?? 0

    let ratio = Double(compressedSize) / Double(uncompressedSize) * 100
    await reportLog(
      level: .notice,
      message: """
        Compressed \(region.displayName): \
        \(byteCountFormatter.string(fromByteCount: Int64(uncompressedSize))) → \
        \(byteCountFormatter.string(fromByteCount: Int64(compressedSize))) \
        (\(String(format: "%.1f", ratio))%)
        """
    )

    return compressedFile
  }

  /// Parses and LZFSE-compresses tiles in parallel, writes sequentially in order.
  ///
  /// This approach parallelizes both CPU-bound parsing and compression while maintaining
  /// sequential writes to the output file. Returns the actual tile index entries (with
  /// compressed sizes) and compression statistics.
  private func parseCompressAndWriteTiles(
    tiles: [TileReference],
    region: TerrainRegion,
    outputResolution: HGTParser.Resolution,
    dataStartOffset: UInt64,
    fileHandle: FileHandle
  ) async throws -> CompressedWriteResult {
    let total = tiles.count

    var indexEntries: [TileIndexInfo] = []
    indexEntries.reserveCapacity(total)

    var stats = CompressionStats()
    var buffer: [Int: CompressedTile] = [:]
    var nextToWrite = 0
    var currentDataOffset = dataStartOffset

    try await withThrowingTaskGroup(of: CompressedTile.self) { group in
      var index = 0

      // Seed initial batch of concurrent parsing + compression tasks
      while index < min(Self.maxConcurrentParsing, tiles.count) {
        let i = index
        let tile = tiles[i]
        group.addTask {
          Self.parseAndCompressTile(tile, index: i, outputResolution: outputResolution)
        }
        index += 1
      }

      // Process results as they complete
      for try await result in group {
        buffer[result.index] = result

        // Write any consecutive ready tiles to maintain file order
        while let tile = buffer.removeValue(forKey: nextToWrite) {
          let entry: TileIndexInfo

          if tile.isVoid {
            // Void tile: no data written, lengths are zero
            entry = TileIndexInfo(
              latitude: tile.latitude,
              longitude: tile.longitude,
              dataOffset: currentDataOffset,
              compressedLength: 0,
              uncompressedLength: 0
            )
            stats.voidTiles += 1
          } else if let compressedData = tile.compressedData {
            // Successfully compressed tile
            try fileHandle.write(contentsOf: compressedData)
            entry = TileIndexInfo(
              latitude: tile.latitude,
              longitude: tile.longitude,
              dataOffset: currentDataOffset,
              compressedLength: UInt32(compressedData.count),
              uncompressedLength: tile.uncompressedLength
            )
            currentDataOffset += UInt64(compressedData.count)
            stats.totalCompressedBytes += compressedData.count
            stats.totalUncompressedBytes += Int(tile.uncompressedLength)
          } else {
            // Failed tile: treat as void
            if let error = tile.error {
              await reportLog(
                level: .warning,
                message:
                  "Failed to parse tile at \(tile.latitude),\(tile.longitude): \(error.localizedDescription)"
              )
            }
            entry = TileIndexInfo(
              latitude: tile.latitude,
              longitude: tile.longitude,
              dataOffset: currentDataOffset,
              compressedLength: 0,
              uncompressedLength: 0
            )
            stats.failedTiles += 1
          }

          indexEntries.append(entry)
          nextToWrite += 1
        }

        // Update progress (tiles written to file)
        await reportProgress(.parsing(region: region, completed: nextToWrite, total: total))
        try Task.checkCancellation()

        // Add next task if more tiles remain
        if index < tiles.count {
          let i = index
          let tile = tiles[i]
          group.addTask {
            Self.parseAndCompressTile(tile, index: i, outputResolution: outputResolution)
          }
          index += 1
        }
      }

      // Write any remaining buffered tiles
      while nextToWrite < total {
        if let tile = buffer.removeValue(forKey: nextToWrite) {
          let entry: TileIndexInfo

          if tile.isVoid || tile.compressedData == nil {
            entry = TileIndexInfo(
              latitude: tile.latitude,
              longitude: tile.longitude,
              dataOffset: currentDataOffset,
              compressedLength: 0,
              uncompressedLength: 0
            )
            if !tile.isVoid { stats.failedTiles += 1 } else { stats.voidTiles += 1 }
          } else {
            let compressedData = tile.compressedData!
            try fileHandle.write(contentsOf: compressedData)
            entry = TileIndexInfo(
              latitude: tile.latitude,
              longitude: tile.longitude,
              dataOffset: currentDataOffset,
              compressedLength: UInt32(compressedData.count),
              uncompressedLength: tile.uncompressedLength
            )
            currentDataOffset += UInt64(compressedData.count)
            stats.totalCompressedBytes += compressedData.count
            stats.totalUncompressedBytes += Int(tile.uncompressedLength)
          }

          indexEntries.append(entry)
        }
        nextToWrite += 1
        await reportProgress(.parsing(region: region, completed: nextToWrite, total: total))
      }
    }

    return CompressedWriteResult(indexEntries: indexEntries, stats: stats)
  }

  // MARK: - Manifest Generation

  /// Generates the terrain manifest JSON file.
  ///
  /// Validates that ALL regions have compressed files in the output directory (not just
  /// the regions processed in this run). This allows partial processing when pre-existing
  /// `.lzma` files are copied to the output directory before running.
  private func generateManifest(for _: [ProcessedRegion]) async throws {
    // Validate that all regions have .lzma files in the output directory
    var missingRegions: [TerrainRegion] = []
    var allRegionData: [(region: TerrainRegion, fileURL: URL, sizeBytes: Int)] = []

    for region in TerrainRegion.allCases {
      let compressedFile = outputLocation.appendingPathComponent(region.compressedFilename)

      if let attrs = try? FileManager.default.attributesOfItem(atPath: compressedFile.path),
        let size = attrs[.size] as? Int
      {
        allRegionData.append((region: region, fileURL: compressedFile, sizeBytes: size))
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
      "version": 2,
      "generatedAt": iso8601Formatter.string(from: Date())
    ]

    if let baseURL {
      manifest["baseURL"] = baseURL
    }

    // Build regions array from all found files (not just processed ones)
    manifest["regions"] = allRegionData.map { data -> [String: Any] in
      [
        "id": data.region.rawValue,
        "filename": data.region.compressedFilename,
        "sizeBytes": data.sizeBytes
      ]
    }

    let jsonData = try JSONSerialization.data(
      withJSONObject: manifest,
      options: [.prettyPrinted, .sortedKeys]
    )

    let manifestFile = outputLocation.appendingPathComponent("terrain-manifest.json")
    try jsonData.write(to: manifestFile)

    await reportLog(
      level: .notice,
      message: "Generated terrain-manifest.json with \(allRegionData.count) regions"
    )
  }

  // MARK: - R2 Upload

  /// Uploads processed files to CloudFlare R2.
  private func uploadToR2Storage(processedRegions: [ProcessedRegion]) async {
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

    // Upload each region file
    for processed in processedRegions {
      await reportProgress(.uploading(region: processed.region, fraction: 0.0))

      do {
        let region = processed.region
        try await uploader.uploadFile(
          at: processed.outputFile,
          key: "terrain/\(region.compressedFilename)",
          onProgress: { fraction in
            await self.reportProgress(.uploading(region: region, fraction: fraction))
          }
        )
      } catch {
        await reportLog(level: .error, message: "R2 upload failed: \(error.localizedDescription)")
        if let onUploadError {
          await onUploadError(error)
        }
      }
    }

    // Upload manifest
    await reportProgress(.uploadingManifest)
    let manifestFile = outputLocation.appendingPathComponent("terrain-manifest.json")
    do {
      try await uploader.uploadFile(at: manifestFile, key: "terrain/terrain-manifest.json")
      await reportLog(level: .notice, message: "Successfully uploaded terrain data to R2")
    } catch {
      await reportLog(
        level: .error,
        message: "R2 manifest upload failed: \(error.localizedDescription)"
      )
      if let onUploadError {
        await onUploadError(error)
      }
    }
  }

  // MARK: - Nested Types

  /// Result of processing a single region.
  private struct ProcessedRegion {
    let region: TerrainRegion
    let outputFile: URL
    let tileCount: Int
  }

  /// Result of a single tile's parse-and-compress operation.
  private struct CompressedTile: Sendable {
    let index: Int
    let latitude: Int
    let longitude: Int
    /// LZFSE-compressed tile data, or nil if parsing/compression failed.
    let compressedData: Data?
    /// Uncompressed size in bytes (0 for void tiles).
    let uncompressedLength: UInt32
    let isVoid: Bool
    let error: Error?
  }

  /// Tile index information for a single compressed tile.
  private struct TileIndexInfo {
    let latitude: Int
    let longitude: Int
    let dataOffset: UInt64
    let compressedLength: UInt32
    let uncompressedLength: UInt32
  }

  /// Result of the parse-compress-write pipeline for all tiles in a region.
  private struct CompressedWriteResult {
    let indexEntries: [TileIndexInfo]
    let stats: CompressionStats
  }

  /// Statistics about per-tile LZFSE compression for a region.
  private struct CompressionStats {
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
