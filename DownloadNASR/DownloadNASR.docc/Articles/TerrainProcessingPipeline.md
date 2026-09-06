# Terrain Processing Pipeline

How terrain data is downloaded, processed, and distributed.

## Overview

The terrain processing pipeline downloads SRTM elevation data, combines it into optimized regional files, and uploads to CloudFlare R2 for distribution. This build-time tool generates the terrain files that `TerrainService` loads at runtime.

The pipeline processes ~14,000 individual 1×1 degree tiles into 11 regional files. Each tile is individually compressed with LZFSE, reducing the total from ~40 GB raw to ~30 GB. Each regional file is then packaged as a Background Assets asset pack, which the system downloads, verifies, and decompresses on the device's behalf.

## Data Sources

### Primary: AWS Terrain Tiles (SRTM1)

The primary data source is AWS Terrain Tiles, which provides public access to SRTM1 data:

- **URL**: `https://elevation-tiles-prod.s3.amazonaws.com/skadi/{lat}/{tile}.hgt.gz`
- **Resolution**: SRTM1 (1 arc-second, ~30m)
- **Coverage**: 60°N to 56°S
- **Format**: Gzip-compressed HGT files

Example: `https://elevation-tiles-prod.s3.amazonaws.com/skadi/N45/N45W123.hgt.gz`

### Fallback: Copernicus GLO-30

For latitudes beyond SRTM coverage (Iceland, Greenland, Arctic Canada), the pipeline falls back to Copernicus GLO-30:

- **URL**: `https://copernicus-dem-30m.s3.amazonaws.com/{folder}/{tile}.tif`
- **Resolution**: 1 arc-second (~30m)
- **Coverage**: 84°N to 85°S
- **Format**: GeoTIFF with DEFLATE compression

### HGT File Format

SRTM HGT files use a simple binary format:

- **Data type**: Big-endian signed 16-bit integers
- **Layout**: Row-major from north to south
- **SRTM1**: 3601×3601 samples (25,934,402 bytes)
- **SRTM3**: 1201×1201 samples (2,884,802 bytes)
- **Void value**: -32768 (no data)

Each file covers a 1×1 degree tile, named by the southwest corner coordinate (e.g., `N45W123.hgt` covers 45-46°N, 122-123°W).

### GeoTIFF Format

Copernicus tiles use Cloud-Optimized GeoTIFF (COG):

- **Compression**: DEFLATE with floating-point predictor
- **Data type**: 32-bit float
- **Layout**: Tiled or stripped organization

The ``GeoTIFFParser`` handles the complexity of TIFF parsing, including decompression and coordinate extraction from filenames.

## Processing Pipeline

### 1. Download Tiles

For each region, the processor downloads all tiles that fall within the region's bounding boxes:

```text
Region: North America
Bounding boxes: 5 (Continental, Alaska, Aleutians, Arctic Canada, Caribbean)
Tiles to download: ~3,500
```

Downloads run in parallel with throttling (20 concurrent requests) to avoid overwhelming the source servers. Missing tiles (ocean areas) are silently skipped.

### 2. Parse Files

Downloaded tiles are parsed to extract elevation data:

- **HGT files**: Decompress gzip, swap byte order (big-endian to little-endian)
- **GeoTIFF files**: Parse TIFF structure, extract raster data, convert float to Int16

### 3. Downsample

SRTM1 data (3601×3601) is downsampled to SRTM3 resolution (1201×1201) using 3×3 block averaging. This reduces file sizes by 9× while maintaining adequate resolution for departure obstacle analysis (~90m).

### 4. Per-Tile LZFSE Compression

Each tile's elevation data is individually compressed using LZFSE (Apple's Compression framework):

- **Void tile detection**: Tiles where all 1,442,401 samples are -32768 (ocean) are stored with zero length, writing no data to the file. This eliminates ~40-50% of tile data for regions with significant ocean coverage.
- **LZFSE compression**: Non-void tiles are compressed with LZFSE, typically achieving 60-70% compression ratio on land tiles. Elevation data compresses well due to spatial correlation between adjacent samples.
- **Variable-size tiles**: Unlike v2 (where all tiles were the same size), v3 tiles have variable compressed sizes. The tile index records each tile's actual compressed and uncompressed lengths.

Expected compression results for North America (~6,700 tiles):

- ~40-50% void tiles (ocean) → 0 bytes each
- ~50-60% land tiles → ~30-40% of original size
- **Overall: ~19 GB uncompressed → ~5-6 GB with LZFSE**

### 5. Combine into Regional Binary

All tiles for a region are combined into a single v3 binary file with:

- 20-byte header (magic, version 3, resolution, tile count, bounding box)
- Tile index (20 bytes per tile: coordinates + offset + compressed length + uncompressed length)
- Contiguous LZFSE-compressed tile data (variable size per tile)

The file format uses little-endian byte order (native to Apple platforms) for efficient on-demand access via `pread`.

### 6. Generate Manifest

A JSON manifest is generated containing:

```json
{
  "version": 3,
  "generatedAt": "2024-01-15T10:30:00Z",
  "baseURL": "https://example.r2.dev/terrain/",
  "regions": [
    {
      "id": "na",
      "filename": "terrain-na.srtm",
      "sizeBytes": 5115763576
    }
  ]
}
```

This manifest ships inside the app, where it supplies the payload sizes the
terrain settings screen displays. It is not what Background Assets reads.

### 7. Package Asset Packs

``AssetPackPublisher`` turns each regional payload into a self-hosted asset
pack, using Xcode's `ba-package` tool. Every pack's ID is the region's
`downloadIdentifier` — `terrain-na` and so on — and its `userInfo` carries the
region ID.

Packs are published with a `prefetch` download policy so the system offers all
of them at install time; the app's Background Assets extension then narrows them
to the one matching the device's locale.

An archive that already postdates its payload is reused rather than rebuilt, so
reprocessing one region does not repackage the other ten.

### 8. Write the Download Manifest

`ba-package download-manifest` writes the index Background Assets reads,
published as `terrain-asset-packs-ios.json`. Each entry's download URL is the
base URL with the pack ID appended, so a pack's R2 object key is
`terrain-packs/<pack ID>` with no extension.

Only rebuilt packs have their versions incremented, because a device
re-downloads a pack when its version rises. The publisher therefore runs
`download-manifest update` against the currently published manifest — fetching
it first if this machine has no local copy — and falls back to
`download-manifest create` only when there is no prior manifest to carry
versions forward from.

### 9. Upload to R2

The regional payloads, the asset-pack archives, the bundled manifest, and the
download manifest are uploaded to CloudFlare R2 for CDN distribution. Archives
go up before the download manifest that indexes them, so a device never reads a
manifest naming a pack the bucket cannot serve yet.

## Output Format

The output binary format is documented in detail in the SF50 Shared framework's Digital Elevation Model article. Key points:

- **Version 3**: Per-tile LZFSE compression with 64-bit file offsets
- **Resolution**: 1201 samples per tile side (SRTM3)
- **Byte order**: Little-endian (native to Apple platforms)
- **On-disk compression**: LZFSE per tile (decompressed on demand at runtime)
- **Download packaging**: one Background Assets asset pack per region (`.aar`),
  which the system decompresses on installation

## Key Components

### SRTMProcessor

``SRTMProcessor`` orchestrates the complete pipeline. It's implemented as an actor for safe concurrent progress reporting:

```swift
let processor = SRTMProcessor(
    regions: [.northAmerica, .europe],
    outputLocation: outputURL,
    logger: logger
)

processor.onProgress = { progress in
    print("Progress: \(progress)")
}

try await processor.process()
```

### HGTParser

``HGTParser`` handles SRTM HGT files:

- Decompresses `.hgt.gz` (gzip) and `.hgt.zip` archives
- Parses coordinates from filenames (`N45W123` -> lat: 45, lon: -123)
- Converts big-endian Int16 values to host byte order
- Detects SRTM1 vs SRTM3 resolution from file size

### GeoTIFFParser

``GeoTIFFParser`` handles Copernicus GeoTIFF files:

- Uses the tiff-ios library for DEFLATE decompression with floating-point predictor
- Extracts coordinates from Copernicus filename convention
- Converts 32-bit float elevations to Int16

### TileProcessing

``TileProcessing`` provides static functions for CPU-bound tile operations:

- **Downsampling**: SRTM1 to SRTM3 using 3×3 block averaging
- **Resampling**: Handles non-square Copernicus tiles at high latitudes
- **Parallel processing**: Functions are not actor-isolated, enabling true parallelism

## Progress Tracking

The processor reports progress through callbacks:

```swift
enum TerrainProgress {
    case pending
    case downloading(region: TerrainRegion, completed: Int, total: Int)
    case parsing(region: TerrainRegion, completed: Int, total: Int)
    case generatingManifest
    case packaging(region: TerrainRegion)
    case uploading(region: TerrainRegion, fraction: Double)
    case uploadingManifest
    case completed
    case cancelled
    case failed(Error)
}
```

## See Also

- ``SRTMProcessor``
- ``AssetPackPublisher``
- ``HGTParser``
- ``GeoTIFFParser``
- ``TileProcessing``
