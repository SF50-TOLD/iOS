# Terrain Processing Pipeline

How terrain data is downloaded, processed, and distributed.

## Overview

The terrain processing pipeline downloads SRTM elevation data, combines it into optimized regional files, and uploads to CloudFlare R2 for distribution. This build-time tool generates the terrain files that ``TerrainService`` loads at runtime.

The pipeline processes ~14,000 individual 1×1 degree tiles into 11 regional files, with LZMA compression reducing total size from ~40 GB to ~3 GB.

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

```
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

### 4. Combine into Regional Binary

All tiles for a region are combined into a single binary file with:

- 20-byte header (magic, version, resolution, tile count, bounding box)
- Tile index (16 bytes per tile: coordinates + offset + length)
- Contiguous elevation data

The file format uses little-endian byte order for efficient memory-mapped access on Apple platforms.

### 5. LZMA Compression

The combined binary is compressed using LZMA, achieving ~12× compression:

### 6. Generate Manifest

A JSON manifest is generated containing:

```json
{
  "version": 2,
  "generatedAt": "2024-01-15T10:30:00Z",
  "baseURL": "https://example.r2.dev/terrain/",
  "regions": [
    {
      "id": "na",
      "filename": "terrain-na.srtm.lzma",
      "sizeBytes": 891234567
    }
  ]
}
```

### 7. Upload to R2

Compressed files and manifest are uploaded to CloudFlare R2 for CDN distribution. The app downloads terrain data from this URL at runtime.

## Output Format

The output binary format is documented in detail in <doc:DigitalElevationModel>. Key points:

- **Version 2**: Uses 64-bit file offsets for large regions
- **Resolution**: 1201 samples per tile side (SRTM3)
- **Byte order**: Little-endian (native to Apple platforms)
- **Compression**: LZMA (decompressed at runtime before memory-mapping)

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
    case compressing(region: TerrainRegion, fraction: Double)
    case generatingManifest
    case uploading(region: TerrainRegion, fraction: Double)
    case uploadingManifest
    case completed
    case cancelled
    case failed(Error)
}
```

## See Also

- ``SRTMProcessor``
- ``HGTParser``
- ``GeoTIFFParser``
- ``TileProcessing``
