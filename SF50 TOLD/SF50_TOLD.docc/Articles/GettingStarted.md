# Getting Started with SF50 TOLD

Configure API credentials before building SF50 TOLD for the first time.

## Overview

SF50 TOLD requires API credentials to fetch NOTAM data. These are stored in a git-ignored xcconfig file.

## Setup

### 1. Create NOTAMAPIConfig.xcconfig

Copy the template and fill in your credentials:

```bash
cp "SF50 TOLD/NOTAM/NOTAMAPIConfig.xcconfig.template" "SF50 TOLD/NOTAM/NOTAMAPIConfig.xcconfig"
```

### 2. Configure NOTAM API Token

The NOTAM API provides real-time FAA NOTAM data for runway closures and conditions.

1. Contact the project maintainer for API access
2. Add to NOTAMAPIConfig.xcconfig:
   - `NOTAM_API_TOKEN` - Your API bearer token
   - `NOTAM_API_BASE_URL` - The API base URL (default: `https://notams.fly.dev`)

## Building

After configuration, build and run SF50 TOLD. If the NOTAM API credentials are missing or invalid:
- The app will still run
- NOTAM features will be unavailable
- A warning will be logged at startup

## Related Configuration

### DownloadNASR Tool

If you're also working with the DownloadNASR tool for processing nav data, see the DownloadNASR target's documentation for its separate credential configuration.
