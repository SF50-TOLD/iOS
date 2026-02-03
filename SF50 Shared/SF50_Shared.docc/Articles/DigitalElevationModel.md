# Digital Elevation Model

Terrain elevation data for departure obstacle clearance analysis.

## Overview

SF50 TOLD uses SRTM (Shuttle Radar Topography Mission) elevation data to analyze terrain along departure paths. This enables pilots to verify obstacle clearance when climbing out from airports in mountainous terrain.

The terrain system consists of:
- **Downloadable region files** - LZMA-compressed binary files containing elevation data
- **Memory-mapped access** - Efficient O(1) coordinate lookups without loading entire files
- **Route profiling** - Generate elevation profiles along flight paths

## Binary File Format

Terrain data is stored in a custom binary format optimized for mobile devices. Files use little-endian byte order (host byte order on Apple platforms).

### Header (20 bytes)

| Offset | Type | Description |
|--------|------|-------------|
| 0 | 4 bytes | Magic: `SRTM` (ASCII) |
| 4 | UInt16 | Version (1 or 2) |
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

### Tile Data

Each tile contains elevation samples as signed 16-bit integers (Int16) in meters. Data is arranged row-major from north to south, with the first sample at the northwest corner.

For SRTM3 resolution (1201×1201 samples), each tile covers 1×1 degree and contains 1,442,401 samples (2,884,802 bytes).

The void/no-data sentinel value is **-32768**. This indicates ocean, lakes, or areas where radar data was unavailable.

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

`MappedTerrainTile` provides memory-mapped file access for O(1) coordinate lookups. Rather than loading the entire file into memory, it maps the file and accesses samples directly via pointer arithmetic.

This enables:
- Fast random access to any coordinate
- Low memory footprint (only accessed pages are loaded)
- Bilinear interpolation for sub-sample precision

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
