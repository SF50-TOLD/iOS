# Weather and Conditions

Working with weather data and atmospheric conditions.

## Overview

SF50 TOLD uses weather data from multiple sources to populate ``Conditions`` objects
for performance calculations. The framework provides loaders for fetching weather
from the National Weather Service, Open-Meteo, and Apple WeatherKit.

## Weather Sources

The ``Conditions/Source`` enum identifies where weather data originated:

- **downloaded**: Fetched from one or more services, listed as ``WeatherProviders``
- **ISA**: International Standard Atmosphere (used when no weather is available)
- **entered**: User-entered manual weather data

Downloaded conditions name every service that contributed, because more than one
usually does. An aviation report is taken first and whatever it leaves unreported is
filled in — from Open-Meteo where it can be, and from Apple WeatherKit otherwise:

- **NWS**: METAR observations and TAF forecasts from the National Weather Service
- **openMeteo**: Forecast model data from [Open-Meteo](https://open-meteo.com)
- **weatherKit**: Current and forecast weather from Apple WeatherKit

## Loading Weather

Use ``WeatherLoader`` to fetch weather data:

```swift
let loader = WeatherLoader()

// Load METAR and TAF
let (metar, taf) = try await loader.loadWeather(
    for: airport.coordinate,
    icaoID: airport.ICAO_ID
)

// Create conditions from METAR
if let metar {
    let conditions = Conditions(observation: metar)
}

// Or from TAF forecast
if let taf {
    let conditions = Conditions(forecast: taf)
}
```

## The Conditions Type

``Conditions`` encapsulates all weather data needed for performance calculations:

- **Wind**: ``Conditions/windDirection`` and ``Conditions/windSpeed``
- **Temperature**: ``Conditions/temperature`` and ``Conditions/dewpoint``
- **Pressure**: ``Conditions/seaLevelPressure``
- **Validity**: ``Conditions/validTime`` indicates when the weather is applicable

### Combining Conditions

When weather data is incomplete, conditions can be combined:

```swift
// Start with METAR conditions
var conditions = Conditions(observation: metar)

// Fill in missing values from a forecast model, crediting it alongside the NWS
conditions = conditions.filling(from: Conditions(weather: currentWeather))
```

### Derived Values

Conditions provides computed values for performance calculations:

- ``Conditions/temperature(at:)`` - Temperature adjusted for elevation
- ``Conditions/densityAltitude(elevation:)`` - Density altitude calculation
- ``Conditions/windsCalm`` - True if wind speed is less than 1 knot

## Winds Aloft, Up and Down

A winds aloft forecast reports at levels that begin some way above the ground — 3,000 feet MSL for
an FAA bulletin, and the lowest pressure level above the model's own terrain for Open-Meteo. How the
gap between that lowest level and the runway is filled is deliberately asymmetric:

- **Downwards, the lowest reported level is carried to the surface.** ``ClimbProfile`` clamps its
  interpolation at both ends, so a departure levelling at 2,000 feet AFE is flown on the 3,000-foot
  wind rather than on nothing. A clamped real wind describes the air better than a fabricated calm,
  and a chart drawn from the same profile shows those carried-down winds rather than an empty band.
- **Upwards, the surface wind is never carried aloft.** Surface wind describes the first few hundred
  feet and nothing above it. Where no forecast covers the flight,
  ``ClimbProfileGenerator/windsAloftObservations(for:conditions:fieldElevation:)`` synthesizes a
  calm column instead of extending the METAR's wind upwards.

The division of labour follows from that: surface winds decide takeoff and landing distance, winds
aloft decide climb performance, and the two are never interpolated into one another.

### The One Thing the Surface May Lend

Temperature is the exception, and only from weather the pilot **entered**.

Where no forecast covers the flight, the synthesized column takes the entered temperature's
deviation from the standard atmosphere at the field and holds that deviation all the way up: a day
fifteen degrees above standard stays fifteen above through the climb. Entered weather is a statement
about the atmosphere to fly through, made when there is nothing else — a go-around planned in the
air, on a number the pilot typed in. Leaving the column standard above the first level would throw
that number away exactly when it is all there is.

A *downloaded* surface temperature gets no such licence. It is an observation of the surface, it
stays at the surface, and the levels above it are standard — because wherever a report can be
downloaded, a forecast covering those levels can be too, and that forecast is what the app uses.
A forecast always wins: an entered temperature never displaces one, and levels a bulletin reports no
temperature for fall back to standard rather than to the surface.

Wind is not in this exception, whatever the source. Pressure needs no exception: an altimeter setting
is already a sea-level value, and carrying it up the standard atmosphere is what pressure altitude
means.

A constant deviation describes a well-mixed air mass, and overstates the temperature aloft under a
surface inversion.

## The Atmosphere Along a Path

``AtmosphericProfile`` describes the temperature, humidity, and cloud in a vertical column above one
point — everything the climb profile's weather layers are drawn from, and deliberately no wind, so
the drawn wind can never disagree with the flown one.

``PathAtmosphereLoader`` samples those columns along a flight path. One column is taken to describe
the air for five nautical miles around it, the radius a TAF is issued for, so a departure that stays
inside that radius needs a single column — and the one over the airport is usually already fetched.
A path that runs further is sampled again at the first point beyond every column already taken.
Open-Meteo answers for many coordinates in one request, so even a procedure climbing tens of miles
downrange costs one round trip. ``PathAtmosphere`` reads across the result: vertically within each
column, then horizontally between them.

### Without a Connection

The two things this app is used for do not have the same weather available to them. Takeoff and
climb are planned on the ground, where a forecast can be fetched. A go-around is planned in the air,
often with no connection at all and on surface weather the pilot has typed in.

What survives that is the point:

- **Terrain, obstacles, and the flight path** are computed from bundled data and need nothing.
- **The winds aloft** the path was flown on are whatever ``WeatherLoader`` already holds, so a
  forecast fetched before departure keeps serving the wind barbs for the rest of the flight.
- **The temperature, cloud, and icing layers** cannot be had, because they are a forecast that has
  to be fetched. ``PathAtmosphereLoader/Failure/offline`` says so, and the picker offers those
  layers as disabled rather than letting them be chosen and come up empty.

``PathAtmosphereLoader`` remembers a refusal for want of a connection across every path rather than
per path, since a device with no signal will not grow one between two recomputations — so switching
departures in the air costs no further waiting. Asking for weather again through
``WeatherLoader/load(force:)`` forgets it.

## See Also

- ``Conditions``
- ``WeatherLoader``
- ``AtmosphericProfile``
- ``PathAtmosphere``
- ``PathAtmosphereLoader``
