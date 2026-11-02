# SF50 TOLD

[![CI](https://github.com/SF50-TOLD/iOS/actions/workflows/ci.yml/badge.svg)](https://github.com/SF50-TOLD/iOS/actions/workflows/ci.yml)
[![Lint](https://github.com/SF50-TOLD/iOS/actions/workflows/lint.yml/badge.svg)](https://github.com/SF50-TOLD/iOS/actions/workflows/lint.yml)
[![App Store](https://img.shields.io/itunes/v/1552835232.svg)](https://apps.apple.com/app/id1552835232)
[![Platform](https://img.shields.io/badge/platform-iOS-lightgrey.svg)](https://developer.apple.com/ios/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A Takeoff and Landing Data (TOLD) calculator for the Cirrus SF50 Vision Jet, G1
through G3.

## ⚠️ Disclaimer

This app has not been approved by the FAA or by Cirrus Aircraft as an official
source of performance information. Always verify performance information with
official sources when using this app.

## Features

### Performance

- **Takeoff**: ground run, distance over a 50 ft obstacle, and climb gradient
- **Landing**: landing distance, ground run, VREF, and go-around climb gradient
- **Climb**: en route climb speed, rate and gradient
- **Climb and go-around profiles**: the predicted climb along a departure or
  missed-approach procedure, plotted against terrain and obstacles
- **Models**: G1, G2, G2+ and G3, with the updated thrust schedule; tabular AFM
  data or regression models
- **Margins**: separate safety factors for dry and contaminated runways, and a
  VREF additive
- **Reports**: Takeoff and Landing Reports (TLRs) to view and share

### Airports, weather and NOTAMs

- **Airports**: FAA NASR, national AIP data sets, open flightmaps and
  OurAirports, merged into one record per airport and updated each cycle, in the
  background while charging
- **Weather**: METAR, TAF and winds aloft from the NWS, filled in from Open-Meteo
  and Apple WeatherKit, or entered by hand
- **NOTAMs**: downloaded NOTAMs sorted by their likely effect on performance;
  runway condition reports and obstacle NOTAMs can fill in contamination,
  displaced thresholds and obstacles
- **Terrain**: downloadable Copernicus DEM regions, delivered as Background
  Assets packs

### Elsewhere

- **Widget**: runway data for the selected airport
- **Shortcuts**: runway numbers through App Intents
- **Units and time**: configurable units, UTC or airport local time

## Project

| Target or directory | Contents |
|---|---|
| `SF50 TOLD/` | The iOS app: SwiftUI views, data loaders, TLR generation, App Intents |
| `SF50 Shared/` | Framework shared with the widget: models, performance models and AFM data, weather, NOTAMs, terrain, SwiftData stores |
| `SF50 Runways/` | The widget extension |
| `TerrainAssets/` | The Background Assets downloader extension for terrain regions |
| `NOTAMParsing/` | Local package that parses NOTAM text |
| `DownloadNASR/` | macOS tool that builds nav data and terrain regions |
| `SF50 SharedTests/`, `SF50 TOLDTests/` | Unit tests (Swift Testing) |
| `SF50 TOLDUITests/` | UI tests |
| `Generate Screenshots/`, `promo/` | App Store screenshots, preview and creative assets |
| `fastlane/` | Release, metadata and promo lanes |

Each target has a DocC catalog (`*.docc`) describing its architecture: the
performance pipeline, data loading, weather, terrain and climb analysis, and
the terrain file format.

Related repositories:

- [NavDataDistribution](https://github.com/SF50-TOLD/NavDataDistribution)
  generates the per-cycle airport, procedure and obstacle data the app
  downloads.
- [Data-Extraction](https://github.com/SF50-TOLD/Data-Extraction) extracts the
  AFM tables and fits the regression models in `SF50 Shared/Data/`.

### Performance data

The tabular model interpolates the AFM tables and reports N/A outside them; the
regression model may extrapolate where that is sensible. Data comes from:

- G1: P/N 31452-001 Rev A1
- G2–G3: P/N 31452-002 Rev A1
- Updated thrust schedule: P/N 31452-111 Rev 1

## Development

### Requirements

- Xcode 27.0 or later (iOS 27.0 deployment target; macOS 27.0 for DownloadNASR)
- Swift 6 language mode
- Ruby and Bundler for fastlane
- pnpm for the promo media

### Setup

Copy `SF50 TOLD/NOTAM/NOTAMAPIConfig.xcconfig.template` to
`NOTAMAPIConfig.xcconfig` and fill in the NOTAM API token and Open-Meteo key.
DownloadNASR reads `DownloadNASR/Credentials.xcconfig`, from its template.

Builds and tests need code signing: the app and widget share data through the
`group.codes.tim.TOLD` app group, and WeatherKit needs its entitlement.

Dependencies are managed with Swift Package Manager.

### Testing

The unit tests run from the `SF50 Shared Unit Tests` test plan and the UI tests
from `SF50 TOLD UI Tests`. The UI tests launch the app with `UI-TESTING`, which
erases its settings, scenarios, NOTAMs and nav data, so don't run them on a
device whose data you want to keep.

### CI

- **CI** builds and runs the unit and UI tests on iPhone and iPad for pushes to
  `main` and `release/**` and for every pull request.
- **Linters** runs `swiftlint --strict` and `swift format lint --strict`.
- **Periphery** checks for unused code.
- **Promo** checks the promo copy and storyboard.
- **Publish Nav Data Store** builds each cycle's SwiftData airport store on a
  Mac and publishes it for the app to download.

### Releases

`CHANGELOG.md` is the App Store release notes: each `## <version>` heading
matches a tag. Pushing a tag runs the Release workflow, which checks the tag
against the project's version and the changelog, archives the app with the next
build number from App Store Connect, and uploads it with the changelog's notes.

### Promo media

[XCUIPromoKit](https://github.com/RISCfuture/XCUIPromoKit) captures and renders
the listing's media from `promo/`: run `pnpm install` there once, then
`fastlane screenshots`, `fastlane preview` or `fastlane creative_assets`. They
build with the selected Xcode, which must be 27.1 or later for the iPhone Duo
simulator. `promo/storyboard.json` and `promo/brand.css` set how they look.
