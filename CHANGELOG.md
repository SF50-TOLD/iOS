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

## 3.8.1

- Version 3.8 closed immediately on launch and never reached the first screen.
  It opens again. Nothing you had saved was affected, and the terrain and
  airport data already on the aircraft are still there.

## 3.8

Terrain data now downloads through iOS itself rather than through the app, and
the airport database arrives ready-built instead of being assembled on the
aircraft.

### Terrain

- A region keeps downloading when you leave the app. iOS carries the transfer,
  shows its own progress, and resumes on its own.
- If iOS reclaims downloaded terrain for storage, Terrain settings marks those
  regions "Removed for space" with a Download button.
- Regions you have already downloaded are kept.

### Performance

- A number the AFM charts do not actually cover now says so. Below the lightest
  weight, the lowest field elevation, or the coldest temperature a chart runs
  to, the app reads the chart's edge — a longer distance than the real
  conditions would give — and marks the figure "offscale low". Landing charts
  start at 0 °C, so this shows up on any cold day.
- Above the range a chart covers, where reading it at the edge would give a
  distance shorter than the truth, no figure is shown at all. This affects
  contaminated-runway corrections and the wind and slope adjustments.
- The en route climb gradient and rate report N/A beyond the conditions their
  data covers, instead of a negative climb.
- On the climb and go-around profiles, the obstacle climb segment says it is
  drawn from the regression model even with the tabular model selected: the AFM
  tabulates no obstacle climb.
- A maximum takeoff weight, the required-gradient warning, and the go-around
  gradient note are now checked against a NOTAMed obstacle under the regression
  model as well as the tabular one.

### Navigation Data

- A database is used only while its cycle is in force; a lapsed one is passed
  over and the current cycle imported.
- An airport the new dataset no longer carries is forgotten along with its
  runway, instead of the widget and Siri failing on a retired one.
- A selection survives a dataset that cannot be read at all.

### Elsewhere

- Drag along the climb or go-around profile to read the terrain height and your
  height above it at any point.
- Each widget names the airport it reports, so several can sit on one screen.
- Ask Siri about a specific runway rather than only about an airport.
- VoiceOver now speaks the runway facts previously carried by color alone.
- When a position cannot be fixed, the app says why.
- Sharing a takeoff or landing report now offers it as text as well as a PDF:
  the whole report in fixed-width columns, to read over a radio or type into a
  scratchpad.
- A shared report is named for the airport, runway, and time it describes, and
  carries that name inside the file.
- Takeoff and landing reports measure their margins against the declared
  distance — TORA, TODA, or LDA, less anything a NOTAM has closed — not the
  whole pavement, so a displaced threshold or clearway no longer reads long.
- A takeoff report marks a runway short, and caps the weight, when the ground
  run does not fit the takeoff run available — not only when the distance to
  50 feet overruns.
- On the landing screen the total distance turns red when it overruns, as the
  takeoff screen already did, and VoiceOver says whether the landing distance
  available is sufficient.
- A departure or arrival time already behind draws its conditions from the
  forecast rather than the current observation.
- VoiceOver speaks a contaminant's depth with its unit, not a prime mark that
  some voices drop.
- A contaminated runway is answered only where the performance data reaches.

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
