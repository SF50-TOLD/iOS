# Digital Elevation Model

Terrain elevation data for departure obstacle clearance analysis.

## Overview

SF50 TOLD uses SRTM (Shuttle Radar Topography Mission) elevation data to analyze terrain along departure paths. This enables pilots to verify obstacle clearance when climbing out from airports in mountainous terrain.

The terrain system consists of:

- **Downloadable region files** - LZMA-compressed binary files containing elevation data
- **On-demand file access** - Efficient O(1) coordinate lookups via `pread` without loading entire files into memory
- **Route profiling** - Generate elevation profiles along flight paths

## Binary File Format

Terrain data is stored in a custom binary format optimized for mobile devices. Files use little-endian byte order (host byte order on Apple platforms).

### Header (20 bytes)

| Offset | Type | Description |
|--------|------|-------------|
| 0 | 4 bytes | Magic: `SRTM` (ASCII) |
| 4 | UInt16 | Version (1, 2, or 3) |
| 6 | UInt16 | Resolution (samples per tile side, e.g., 1201) |
| 8 | UInt32 | Tile count |
| 12 | Int16 | Minimum latitude |
| 14 | Int16 | Maximum latitude |
| 16 | Int16 | Minimum longitude |
| 18 | Int16 | Maximum longitude |

### Tile Index

Following the header is an index entry for each tile. Entry size depends on file version:

**Version 1 (12 bytes per entry):**

| Offset | Type | Description |
|--------|------|-------------|
| 0 | Int16 | Tile latitude (SW corner) |
| 2 | Int16 | Tile longitude (SW corner) |
| 4 | UInt32 | Data offset from file start |
| 8 | UInt32 | Data length in bytes |

**Version 2 (16 bytes per entry):**

| Offset | Type | Description |
|--------|------|-------------|
| 0 | Int16 | Tile latitude (SW corner) |
| 2 | Int16 | Tile longitude (SW corner) |
| 4 | UInt64 | Data offset from file start |
| 12 | UInt32 | Data length in bytes |

Version 2 uses 64-bit offsets to support files larger than 4 GB.

**Version 3 (20 bytes per entry):**

| Offset | Type | Description |
|--------|------|-------------|
| 0 | Int16 | Tile latitude (SW corner) |
| 2 | Int16 | Tile longitude (SW corner) |
| 4 | UInt64 | Data offset from file start |
| 12 | UInt32 | Compressed length in bytes |
| 16 | UInt32 | Uncompressed length in bytes |

Version 3 adds per-tile LZFSE compression. Each tile's elevation data is independently compressed, enabling on-demand decompression without loading the entire file into memory.

### Tile Data

**Version 1/2:** Each tile contains elevation samples as signed 16-bit integers (Int16) in meters, stored uncompressed. Data is arranged row-major from north to south, with the first sample at the northwest corner.

**Version 3:** Each tile's Int16 elevation data is compressed with LZFSE (Apple's Compression framework). Tiles are decompressed individually on demand into a small LRU cache (~30 MB / 10 tiles).

For SRTM3 resolution (1201×1201 samples), each uncompressed tile contains 1,442,401 samples (2,884,802 bytes). With LZFSE compression, land tiles typically compress to 30-40% of their original size.

### Void Tile Optimization (v3)

The void/no-data sentinel value is **-32768**. This indicates ocean, lakes, or areas where radar data was unavailable.

In v3 files, tiles where all samples are void (pure ocean) are stored with `compressedLength = 0` and `uncompressedLength = 0`, with no data written to the file. On read, any coordinate in such a tile returns the void value. This eliminates ~40-50% of tile data for regions with significant ocean coverage.

## Regions

Terrain data is organized into 11 downloadable regions:

| Region | Code | Coverage |
|--------|------|----------|
| North America | `na` | Continental US, Canada, Mexico, Caribbean, Alaska |
| South America | `sa` | South America, Galapagos |
| Europe | `eu` | Europe, UK, Iceland, Greenland, Svalbard |
| Asia | `as` | East/Southeast/South Asia, Siberia |
| Middle East | `me` | Arabian Peninsula, Turkey, Iran |
| Africa | `af` | Continental Africa |
| Australia | `au` | Australia, New Zealand, Papua New Guinea, Pacific islands |
| Oceania | `oc` | Hawaii, French Polynesia, Micronesia |
| Mid-Atlantic | `ma` | Azores, Canary Islands, Cabo Verde, Madeira |
| Indian Ocean | `io` | Seychelles, Mauritius, Maldives |
| Antarctica | `aq` | Antarctic continent |

Use ``TerrainRegion/containing(latitude:longitude:)`` to find which regions contain a given coordinate. Multiple regions may overlap at boundaries.

## Architecture

### TerrainService

``TerrainService`` is the main entry point for terrain queries. It's implemented as an actor for thread-safe access:

```swift
let service = TerrainService.shared

// Load a region
try await service.loadRegion(.northAmerica, from: terrainFileURL)

// Query elevation at a point
if let elevation = await service.elevation(at: coordinate) {
    print("Elevation: \(elevation.converted(to: .feet))")
}
```

### MappedTerrainTile

`MappedTerrainTile` provides on-demand file access for O(1) coordinate lookups. Rather than loading the entire file into memory, it opens a file descriptor at initialization and reads individual elevation samples via `pread` (POSIX positional read). Only the header and tile index (~100 KB) are held in memory.

For v3 files, tile data is LZFSE-compressed on disk. On first access, a tile is decompressed into an LRU cache (up to ~30 MB / 10 tiles). Subsequent reads from the same tile are served directly from the cache. Since terrain profile queries are spatially localized (typically touching 1-3 tiles), the cache hit rate is very high after the first query in a tile.

This enables:

- Fast random access to any coordinate
- Minimal memory footprint regardless of file size
- Bilinear interpolation for sub-sample precision
- Thread-safe concurrent queries (cache protected by `OSAllocatedUnfairLock`)

### TerrainRegion

``TerrainRegion`` defines the 11 downloadable regions with their bounding boxes. Each region may have multiple non-contiguous bounding boxes (e.g., North America includes separate boxes for Alaska and the Caribbean).

### TerrainManifest

``TerrainManifest`` contains metadata about available terrain downloads, loaded from a bundled JSON file. It provides:

- Download URLs
- File sizes for accurate progress reporting
- Version information

## Usage Examples

### Point Elevation Query

```swift
let service = TerrainService.shared

// Ensure region is loaded
if !await service.isRegionLoaded(.northAmerica) {
    try await service.loadRegion(.northAmerica, from: fileURL)
}

// Query elevation
let coordinate = CLLocationCoordinate2D(latitude: 39.8561, longitude: -104.6737)
if let elevation = await service.elevation(at: coordinate) {
    print("Denver Airport: \(elevation.converted(to: .feet))")
    // Output: Denver Airport: 5431 ft
}
```

### Route Profile

```swift
let departure = CLLocationCoordinate2D(latitude: 39.8561, longitude: -104.6737)
let waypoint = CLLocationCoordinate2D(latitude: 39.6, longitude: -105.1)

let profile = await service.profile(
    along: [departure, waypoint],
    sampleIntervalNM: 0.5
)

print("Max terrain: \(profile.maxElevation?.converted(to: .feet) ?? 0)")
print("Points sampled: \(profile.points.count)")
```

## See Also

- ``TerrainService``
- ``TerrainRegion``
- ``TerrainProfile``
- ``TerrainProfilePoint``
