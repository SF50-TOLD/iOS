# TODO

Work still outstanding, with enough context to pick each item up cold, followed by the options that
have been ruled out and why.

## Persist the landing flap setting and anti-ice

`flapSetting` lives as in-memory `@Observable` state on `BasePerformanceViewModel`, seeded from a
`defaultFlapSetting` init argument, and anti-ice is encoded in the `FlapSetting` cases rather than
stored. So a landing flap selection does not survive relaunching the app.

This gates the landing path only. `flapSetting` reaches performance solely through
`loader.landingPrefix(for:)` and `loader.vrefPrefix(for:)`, and `iceProtection` solely through the
three enroute-climb accessors — all in
`SF50 Shared/Performance/Models/TabularPerformanceModel.swift`. Takeoff distance depends on neither,
and the takeoff screen has no flap or IPS control: it renders a fixed `Text("50%")` and
`Text("As Required")`.

The landing flap setting is already an App Intents parameter defaulting to flaps 100, so a widget or
a shortcut states the configuration its number came from rather than inheriting an unstated one.
Persisting it would let the app's own landing screen do the same.

---

## Smaller items

- [ ] **`availableLandingRun` returns the landing *distance* available, not the ground run.**
      `LandingPerformanceViewModel.availableLandingRun` is
      `runway?.availableLandingDistance(notamedBy:)`, and it is passed as `maximum:` to both
      `LandingGroundRunView` and `LandingDistanceView`. The arithmetic is right — a landing has one
      declared distance, unlike a takeoff, which is why `Runway` has `availableTakeoffRun` and
      `availableTakeoffDistance` but only `availableLandingDistance`. The name is what is wrong, in
      code where a reader has to trust that a length is the length it claims to be. Rename the
      property to `availableLandingDistance` and the two call sites with it.
- [ ] **`WeatherLoader.Key.isCurrent` treats past times as current.**
      `SF50 Shared/Weather/WeatherLoader+Conditions.swift`: `time.timeIntervalSinceNow < 3600` is
      unsigned, so a time an hour *behind* now takes the `currentWeather` arm rather than the hourly
      forecast.
- [ ] **`for await … where !Task.isCancelled` skips instead of breaking.** A `where` clause on
      `for await` *filters* the element; it does not exit the loop. On cancellation these keep
      draining the stream and discarding everything, and for a stream that never ends on its own —
      `Defaults.updates(_:)` — the task never exits at all. Sixteen sites in four files:
      `WeatherViewModel.swift` (5), `BasePerformanceViewModel.swift` (5),
      `ClimbPerformanceViewModel.swift` (3), `NavDataLoaderViewModel.swift` (3). The location code
      already uses an explicit `break` and is the pattern to follow. The sibling CTA Helper app has
      the same idiom and the same bug.
- [ ] **Generating two TLRs concurrently deadlocks.** Two Swift Testing suites that each call
      `generateTakeoffReport` in parallel both hang and never return; running the same tests serially
      passes in well under a second. The `Takeoff Report` suite is marked `.serialized` to work
      around it. The app only ever builds one report at a time, so nothing is broken in the cockpit —
      but the shared state behind it is unidentified, and it constrains how the report path can be
      tested.
- [ ] **`RunwayRow` contamination wording is duplicated** from
      `BaseReportTemplate.format(contamination:)`, which is a method on the HTML report class and
      unreachable from a view. A shared `Contamination` description on `SF50 Shared` would give one
      source of truth.
- [ ] **Signposts on the CIFP and OurAirports loads — needs a PR in another repo.** Those parsers
      live in the `NavDataGeneration` library of the sibling `NavDataDistribution` package, are
      imported only by the macOS `DownloadNASR` target, and use swift-log rather than `os`.
      Everything reachable from this repo is instrumented.

---

## Considered and rejected

Recorded so they do not get re-proposed.

- **Live Activity for terrain downloads** — the system draws one itself for a managed asset-pack
  download, including progress and a cancel control. There is nothing left to build.
- **Control Center / Lock Screen controls** — requires a navigation layer the app does not have (no
  `onOpenURL`, no `CFBundleURLSchemes`, no `NSUserActivity`, no `widgetURL`), and `NOTAMView` is not
  addressable at all. `AirportEntity` does not change this: it identifies an airport, it does not
  route to a screen. Revisit only if routing gets built for other reasons.
- **Foundation Models NOTAM extraction** — the safety fence would be a UI convention rather than a
  type invariant, and downloaded NOTAMs are not runway-attributed, so extraction must also decide
  *which* NOTAM applies — an attribution problem where a wrong answer is worse than no answer.
- **`#Index(.rtree(…))` on `Obstacle` / `Airport`** — SQLite's R\*Tree wants coordinate columns in
  min/max *pairs*, so `.rtree([\._latitude, \._longitude])` most plausibly indexes nothing. The
  existing binary index already gives a range scan. Profile before migrating a schema.
- **CloudKit sync for `Scenario`** — permanent, one-way cost (new container, entitlements, background
  mode, second `ModelConfiguration` in two targets, additive-only schema forever). Establish that
  pilots hand-author scenarios worth carrying between devices first.
- **`.tabViewStyle(.sidebarAdaptable)` / `scrollEdgeEffectStyle(.hard)`** — cosmetic, and the former
  breaks `TabBarPage.tapUntilSelected` and the fastlane screenshot lane.
- **ATIS voice transcription** — a from-scratch aviation-phraseology parser for four typed fields,
  half of whose vocabulary has nowhere to land (`Conditions` has no gust or RVR property).
- **`WeatherQuery.alerts`** — puts a non-aviation NWS product beside legally-relevant numbers, and
  gives back the savings that trimming the weather payload won.
- **MetricKit** — sentry-cocoa 9.26 has App Hangs V2 on by default and an `enableMetricKit` bridge.
- **`ModelContext.fetchHistory` for widget reloads** — diagnoses a real bug (`reloadTimelines`
  appears exactly once, on a defaults-change observer) but the fix is calling it at the
  `NavDataLoader` and `NOTAMLoader` completion sites.
- **`Chart3D`** — adds no number the 2D profile lacks, and its `SurfacePlot` is an
  analytic-function API.
- **Background Assets for the nav-data store** — tempting on the terrain precedent, and wrong.
  Managed asset packs are purgeable: the system reclaims one under storage pressure without telling
  the app, and `AssetPackManager.url(for:)` answers with a path whether or not anything is behind it,
  so a `ModelConfiguration` aimed at it opens an *empty* store. Terrain survives that; an empty
  airport database is the failure the store project existed to remove. Publishing also needs
  `xcrun ba-package` on a Mac, and one pack per 28-day cycle turns the manifest into a growing
  ledger.
- **Replacing the nav-data store file in place** — `FileManager.replaceItemAt` leaves any reader on a
  deleted inode, and the app is not the only process holding that store: the widget and the App
  Intents surfaces open it too. Hence numbered generations, switched to by recording a number and
  reclaimed only at a launch that holds none of them. Do not collapse that back into one file.
- **Moving the `@Model` types into the `NavData` package** — SwiftData does not exist on Linux either
  way, so an Apple host is required regardless; it would only fragment the schema across two repos
  behind a semver pin, which is what the schema fingerprint exists to prevent. `DownloadNASR` links
  `SF50 Shared` directly instead.
