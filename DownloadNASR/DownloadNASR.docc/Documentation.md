# ``DownloadNASR``

macOS tool for processing navigation and terrain data into app-ready format.

## Overview

DownloadNASR is a macOS utility that processes data from multiple sources into
compressed formats used by SF50 TOLD:

- **Navigation data**: Airport and runway records from FAA NASR and OurAirports, instrument procedures from FAA CIFP, and obstacles from FAA DOF
- **Terrain data**: SRTM and Copernicus elevation tiles combined into regional binary files

Processed data is optionally uploaded to GitHub (nav data) or CloudFlare R2
(terrain data) for distribution.

## Topics

### Getting Started

- <doc:GettingStarted>

### Navigation Data Processing

- <doc:NavDataProcessingPipeline>
- ``NavDataProcessorViewModel``

### Terrain Processing

- <doc:TerrainProcessingPipeline>
- ``SRTMProcessor``
- ``HGTParser``
- ``GeoTIFFParser``
- ``TileProcessing``
- ``BinaryFileWriter``
- ``TerrainProcessorViewModel``

### Upload Services

- ``R2Uploader``
- ``GitHubUploader``
- ``GitHubAPIError``

### Configuration

- ``CredentialsConfig``
