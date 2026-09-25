# Terrain Processing Pipeline

How terrain data is downloaded, processed, and distributed.

## Overview

The terrain processing pipeline downloads Copernicus DEM elevation data, combines it into optimized regional files, and uploads to CloudFlare R2 for distribution. This build-time tool generates the terrain files that `TerrainService` loads at runtime.

The pipeline turns every 1×1 degree tile inside 11 regions' bounding boxes into one regional file per region, each tile individually compressed with LZFSE. Each regional file is then packaged as a Background Assets asset pack, which the system downloads and installs on the device's behalf.

## Data Source

Terrain is the surface an aircraft can hit: the water surface over the sea and lakes, and the ground everywhere else, including ground below sea level (Death Valley, the Dead Sea's surface). The Copernicus DEM is a digital surface model with exactly that property, so it is the only source. Elevation sources that merge in bathymetry, such as the AWS Terrain Tiles ("skadi"), would put terrain over the sea on the seafloor, thousands of meters below the surface, and are not used.

``CopernicusTileCatalog`` decides where each tile comes from, using each product's published `tileList.txt`:

- **GLO-30** (1 arc-second, ~30 m), `https://copernicus-dem-30m.s3.amazonaws.com`, wherever it is published.
- **GLO-90** (3 arc-seconds, ~90 m), `https://copernicus-dem-90m.s3.amazonaws.com`, for the tiles withheld from GLO-30's public release (Armenia and Azerbaijan). GLO-90 is published for every GLO-30 tile as well.
- **Open sea**: a tile neither product publishes contains no land, so it is written as sea level throughout, not left out. A tile left out of a payload reads as "no data".

Heights are relative to the EGM2008 geoid, and include buildings and vegetation, both of which an aircraft can hit.

### GeoTIFF Format

Every Copernicus tile is a Cloud-Optimized GeoTIFF in one layout, which ``GeoTIFFParser`` decodes directly and rejects anything else:

- **Image**: the first image of a classic little-endian TIFF, one band of 32-bit floats
- **Organization**: square tiles (1024 or 2048 pixels on a side)
- **Compression**: DEFLATE with the floating-point predictor
- **Grid**: point-registered, `width` samples per degree from the tile's west edge and 3600 per degree from its north edge. The east and south edges belong to the neighbouring tiles. Tiles narrow towards the poles, e.g. 1200×3600 at 70°N.

## Processing Pipeline

### 1. Build Each Tile

For each region, the processor streams every tile in the region's bounding boxes through download, decode, resample and compression, eight at a time, deleting each GeoTIFF once it is compressed:

```text
Region: North America
Bounding boxes: 5 (Continental, Alaska, Aleutians, Arctic Canada, Caribbean)
Tiles: ~6,700
```

A download that still fails after retries, or a tile that cannot be decoded, fails the region: a payload with a hole in it is never published.

### 2. Decode

``GeoTIFFParser`` inflates each GeoTIFF tile, undoes the floating-point predictor, and rounds each sample to whole meters as `Int16`.

### 3. Resample

Each tile is resampled onto the SRTM3 grid, 1201×1201 samples including both edges, by bilinear interpolation. Output sample `k` sits at source position `k × width / 1200`, so a GLO-30 tile's output samples fall exactly on every third source sample. The last row and column lie past the tile's own samples and take its outermost ones.

### 4. Per-Tile LZFSE Compression

Each tile's elevation data is individually compressed using LZFSE (Apple's Compression framework):

- **Void tile detection**: Tiles where all 1,442,401 samples are -32768 (no data) are stored with zero length, writing no data to the file. Open-sea tiles are sea level, not void; being uniform, each compresses to a few kilobytes.
- **LZFSE compression**: Non-void tiles are compressed with LZFSE, typically achieving 60-70% compression ratio on land tiles. Elevation data compresses well due to spatial correlation between adjacent samples.
- **Variable-size tiles**: Unlike v2 (where all tiles were the same size), v3 tiles have variable compressed sizes. The tile index records each tile's actual compressed and uncompressed lengths.

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

Beside the payload, each pack carries `terrain-<id>.srtm.sha256`, the payload's
SHA-256 in hexadecimal. Background Assets verifies nothing about a pack's
contents, so the app checks the payload against it. Because the digest travels
inside the pack, it always describes the version installed.

Packs are published with a `prefetch` download policy so the system offers all
of them at install time; the app's Background Assets extension then narrows them
to the one matching the device's locale.

An archive that already postdates its payload and digest is reused rather than
rebuilt, so reprocessing one region does not repackage the other ten.

### 8. Write the Download Manifest

`ba-package download-manifest` writes the index Background Assets reads,
published as `terrain-asset-packs-ios.json`. Each entry's download URL is the
base URL with the pack ID appended.

A device updates an installed pack when its version rises, on its own schedule,
whichever version of the app is installed. So only packs whose payload changed
have their versions incremented: each pack's `userInfo` carries its payload's
SHA-256, which `ba-package` copies into the download manifest, and a pack whose
manifest entry lacks its current digest is one that changed. That holds however
many runs it takes to publish, a failed one included. Each run's changed packs
are published under a base URL of their own, `terrain-packs/<release stamp>/`, where the stamp is the run's
UTC start time (e.g. `20260924T031500Z`). A published archive is never
replaced: a device part-way through downloading one keeps getting the same
bytes.

The publisher runs `download-manifest update` against the currently published
manifest — fetching it first if this machine has no local copy — and falls back
to `download-manifest create` only when there is no prior manifest to carry
versions forward from. `update` accepts only asset-pack paths ending in `.json`,
so each archive is passed through a `.json`-named hard link (the tool takes the
pack's download size from the path, so a symbolic link would report its own few
bytes), each behind its own `--asset-pack-paths` flag. `ba-package` is run
directly from the developer directory, since `xcrun` refuses to run inside the
app's sandbox. A pack must never be
dropped from the manifest: devices treat a pack the manifest no longer lists as
obsolete and delete it.

### 9. Upload to R2

The regional payloads and `terrain-manifest-v3.json` serve builds that download
payloads directly. The asset-pack archives and the download manifest serve
Background Assets. Uploads follow the download manifest: each archive goes to
the key its URL names, unless an object is already there. Any failed upload
stops the run before a manifest goes up, and the download manifest goes last,
so a device never reads a manifest naming a file the bucket cannot serve.

To publish payloads already built, for example after checking a run made with
`TERRAIN_SKIP_UPLOAD=1`, run headless with `TERRAIN_REGIONS=none`: it packages
and uploads what the output directory holds without rebuilding anything.

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

### CopernicusTileCatalog

``CopernicusTileCatalog`` reads each Copernicus product's tile list and says
whether a tile comes from GLO-30, from GLO-90, or is open sea.

### GeoTIFFParser

``GeoTIFFParser`` decodes Copernicus GeoTIFF files:

- Reads the first image file directory of a classic little-endian TIFF, and rejects any layout other than Copernicus's
- Inflates each DEFLATE-compressed tile and undoes the floating-point predictor
- Rounds 32-bit float elevations to Int16

### TileProcessing

``TileProcessing`` provides static functions for CPU-bound tile operations:

- **Resampling**: Places each Copernicus tile, square or narrowed at high latitudes, on the SRTM3 grid
- **Open sea**: Produces the sea-level tile for tiles no Copernicus product publishes
- **Parallel processing**: Functions are not actor-isolated, enabling true parallelism

## Progress Tracking

The processor reports progress through callbacks:

```swift
enum TerrainProgress {
    case pending
    case building(region: TerrainRegion, completed: Int, total: Int)
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
- ``CopernicusTileCatalog``
- ``GeoTIFFParser``
- ``TileProcessing``
