import SwiftUI

/// A date-and-time field for the takeoff/landing configuration forms.
///
/// Normally this is a compact `DatePicker`. During screenshot generation it renders a static,
/// visually-equivalent row instead: the compact picker’s internal time label
/// (`_UIDatePickerCompactTimeLabel`) reports a contradictory automation type on iOS 26, which makes
/// XCUITest fail to compute the accessibility snapshot for any query while it is on screen. Omitting
/// the live picker keeps that element out of the automation tree so screenshot capture stays
/// reliable, while the displayed date and time remain identical.
struct DateField: View {
  /// How far ahead WeatherKit publishes an hourly forecast.
  private static let forecastHorizonDays: TimeInterval = 10,
    secondsPerDay: TimeInterval = 86400

  let title: LocalizedStringKey
  @Binding var time: Date
  let timeZone: TimeZone

  /// The furthest out a time can be planned and still have a forecast behind it.
  ///
  /// Past this the picker would keep accepting dates that no weather service answers for, leaving
  /// the performance figures standing on ISA conditions with nothing on screen to say so.
  private var latestPlannableTime: Date {
    Date().addingTimeInterval(Self.forecastHorizonDays * Self.secondsPerDay)
  }

  var body: some View {
    if UITestingHelper.isGeneratingScreenshots {
      StaticDateField(title: title, time: time, timeZone: timeZone)
    } else {
      DatePicker(title, selection: $time, in: Date()...latestPlannableTime)
        .environment(\.timeZone, timeZone)
        .accessibilityIdentifier("dateSelector")
    }
  }

  init(_ title: LocalizedStringKey, time: Binding<Date>, timeZone: TimeZone) {
    self.title = title
    self._time = time
    self.timeZone = timeZone
  }
}

/// A read-only stand-in for the compact `DatePicker`, styled to resemble its date and time pills.
private struct StaticDateField: View {
  let title: LocalizedStringKey
  let time: Date
  let timeZone: TimeZone

  private var dateStyle: Date.FormatStyle {
    var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
    style.timeZone = timeZone
    return style
  }

  private var timeStyle: Date.FormatStyle {
    var style = Date.FormatStyle(date: .omitted, time: .shortened)
    style.timeZone = timeZone
    return style
  }

  var body: some View {
    HStack {
      Text(title)
      Spacer()
      pill(time.formatted(dateStyle))
      pill(time.formatted(timeStyle))
    }
  }

  private func pill(_ text: String) -> some View {
    Text(text)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
  }
}

#Preview("Date Picker") {
  @Previewable @State var time = Date.now

  Form {
    DateField("Date", time: $time, timeZone: .current)
  }
}

#Preview("Static") {
  Form {
    StaticDateField(title: "Date", time: .now, timeZone: .current)
  }
}
