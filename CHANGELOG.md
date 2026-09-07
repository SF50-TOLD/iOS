# Changelog

Release notes for SF50 TOLD. The version headings are what
`Scripts/release-notes.sh` reads and what the Release workflow writes into App
Store Connect's "What's New" — so a heading is `## <version>`, matching the tag
exactly.

Write the entries to survive both renderings. The changelog is read as Markdown
here and as plain text on the store, where the field shows whatever it is given
verbatim: a line that only makes sense with its formatting will read badly in
one of the two places.

These notes are read by pilots deciding whether to update, so they describe what
changed in the cockpit rather than what changed in the code.

## 3.8

Terrain data now downloads through iOS itself rather than through the app.

### Terrain

- A region keeps downloading when you leave the app. Tapping Download and
  switching to another app used to stall the transfer, which mattered for
  regions that run to several gigabytes. iOS now carries the transfer, shows its
  own progress, and resumes on its own.
- If iOS reclaims downloaded terrain to free up storage, the app tells you which
  regions went missing instead of quietly showing them as never downloaded.
  Terrain settings marks them "Removed for space" with a Download button.
- Regions you have already downloaded are kept. Updating re-downloads nothing.

### Elsewhere

- Drag along the climb or go-around profile to read the terrain height and your
  height above it at any point on the path.
- Each widget names the airport it reports, so several can sit on one screen
  showing different fields.
- Ask Siri about a specific runway rather than only about an airport.
- VoiceOver now speaks the runway facts that were previously carried by color
  alone.
- When a position cannot be fixed, the app says why rather than showing nothing.
- Scrubbing a terrain profile is smoother on long paths.

## 3.7.1

- Terrain now downloads after the app finishes installing rather than during it,
  so the app is usable straight away instead of waiting on several gigabytes.
- Download progress is reported by the transfer that is actually running, so the
  percentage advances instead of sitting still.
- A region reports the size it actually measures rather than an estimate of what
  it might have been.

## 3.7

### Weather

- The climb profile chart shows the weather the climb is flown through.
- Winds aloft are interpolated for airports that are not themselves reporting
  stations, instead of being left blank.
- The winds aloft forecast served is the one published for the time you planned
  for.
- Gaps in downloaded weather are filled from Open-Meteo.

### Nav data and stability

- Importing nav data takes about half as long.
- Running out of storage mid-import is now reported as a full disk rather than
  as an unexplained failure.
- Fixed a crash that could occur when reading a runway's surface type.
- The airport search field no longer lingers after its picker closes.

## 3.6.2

- Loading nav data no longer blocks the app while it decodes, so launching after
  an update stops hanging.
- An Aviation Weather outage is reported as an outage rather than as a defect in
  the app.

## 3.6.1

- Resetting nav data no longer freezes the app partway through.
- Nav data is distributed as a Swift package, which makes updates smaller and
  more reliable.

## 3.6.0

- Updated for iOS 26.
- Fixed a hang that could occur at launch while waiting for data to load, and
  the transient errors that came with it.
