import CoreLocation
import Foundation

extension PathAtmosphere {

  /// The lapse rate the sample columns cool at, in °C per thousand feet.
  private static let previewLapseRateC = 2.0

  /// How far apart the sample columns of a multi-column atmosphere stand, in nautical miles.
  private static let previewColumnSpacingNM = 6.0

  /// How many columns a multi-column sample atmosphere has.
  private static let previewColumnCount = 4

  /// A cold, damp day over a field at sea level.
  ///
  /// Only just above freezing at the surface. The shortest path a preview plots is a
  /// runway-heading departure, which tops two thousand feet above the field: warmer than this and
  /// the freezing level, and the icing that grades upwards from it, sit above that chart entirely.
  private static let seaLevelColumn = SampleColumn(
    seaLevelC: 1,
    decks: [1000: 0.2, 2000: 0.45, 4000: 0.7, 5000: 0.95],
    humidBandFt: 1000...6000
  )

  /// A warm day over a mountain field.
  ///
  /// A column is anchored at sea level however high the field is, so the cold column above reads
  /// as an arctic day by the time it reaches eight thousand feet. This one is warm enough at sea
  /// level to be pleasant up there, with its decks and its freezing level in the band a departure
  /// from such a field actually climbs through.
  private static let mountainColumn = SampleColumn(
    seaLevelC: 26,
    decks: [9000: 0.3, 10000: 0.6, 12000: 0.9, 13000: 0.95],
    humidBandFt: 9000...15000
  )

  /// A sample atmosphere over a short path, as a departure inside one column's reach gets.
  ///
  /// Four decks below six thousand feet, one of each coverage, with the upper ones cold enough and
  /// damp enough to ice — so every layer has something to draw inside the plotted band.
  public static var preview: Self {
    .init(columns: [column(seaLevelColumn, distanceNM: 0)], providers: .openMeteo)
  }

  /// A sample atmosphere over a path long enough to need several columns.
  ///
  /// The columns cool downrange and their decks thin out, so the layers visibly change across them
  /// and the freezing level slopes rather than ruling flat.
  public static var previewMultiColumn: Self { multiColumn(seaLevelColumn) }

  /// A sample atmosphere for a departure from a field high in the mountains.
  public static var previewMountain: Self { multiColumn(mountainColumn) }

  private static func multiColumn(_ sample: SampleColumn) -> Self {
    .init(
      columns: (0..<previewColumnCount).map { index in
        column(
          sample,
          distanceNM: Double(index) * previewColumnSpacingNM,
          coolingC: Double(index) * 0.25,
          coverageScale: 1 - Double(index) * 0.18
        )
      },
      providers: .openMeteo
    )
  }

  private static func column(
    _ sample: SampleColumn,
    distanceNM: Double,
    coolingC: Double = 0,
    coverageScale: Double = 1
  ) -> Column {
    let levels = stride(from: 0.0, through: 18000.0, by: 1000.0).map { altitudeFt in
      AtmosphericProfile.Level(
        altitude: .init(value: altitudeFt, unit: .feet),
        temperature: .init(
          value: sample.seaLevelC - coolingC - previewLapseRateC * altitudeFt / 1000,
          unit: .celsius
        ),
        relativeHumidity: sample.humidity(atAltitudeFt: altitudeFt),
        cloudCover: sample.cloudCover(atAltitudeFt: altitudeFt) * coverageScale
      )
    }

    return .init(
      distanceNM: distanceNM,
      profile: .init(
        coordinate: .init(latitude: 37.72, longitude: -122.22),
        validTime: .init(start: .now, duration: 3600),
        levels: levels
      )
    )
  }

  /// The shape of a sample column: how warm it is, where its cloud is, and where it is damp.
  private struct SampleColumn {

    /// The temperature at sea level, in °C, which the lapse rate cools from.
    let seaLevelC: Double

    /// How much sky each deck covers, keyed by the altitude it is reported at.
    ///
    /// Reported at levels rather than over bands: a deck is drawn at the altitude it is reported
    /// for, so a band would only stack it into one thick bar.
    let decks: [Double: Double]

    /// Where the column is damp enough to count as carrying visible moisture.
    let humidBandFt: ClosedRange<Double>

    func cloudCover(atAltitudeFt altitudeFt: Double) -> Double { decks[altitudeFt] ?? 0 }

    /// Damp through the band the cloud sits in and dry outside it, so the icing layer picks out
    /// the cold part of that band.
    func humidity(atAltitudeFt altitudeFt: Double) -> Double {
      humidBandFt.contains(altitudeFt) ? 0.9 : 0.4
    }
  }
}
