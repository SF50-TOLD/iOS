import Foundation

extension WeatherLoader {
  func removeConditionsSubscriber(id: UUID) {
    conditionsSubscribers.removeValue(forKey: id)
  }

  func removeMetarSubscriber(id: UUID) {
    metarSubscribers.removeValue(forKey: id)
  }

  func removeTafSubscriber(id: UUID) {
    tafSubscribers.removeValue(forKey: id)
  }

  func removeWindsAloftSubscriber(id: UUID) {
    windsAloftSubscribers.removeValue(forKey: id)
  }

  func notifySubscribers() async {
    // Notify conditions subscribers
    for (_, (key, continuation)) in conditionsSubscribers {
      let conditions = await conditions(for: key)
      continuation.yield(conditions)
    }

    // Notify METAR subscribers
    for (_, (key, continuation)) in metarSubscribers {
      let raw = observations.map { $0[key.id]?.raw }
      continuation.yield(raw)
    }

    // Notify TAF subscribers
    for (_, (key, continuation)) in tafSubscribers {
      let raw = forecasts.map { $0[key.id]?.raw }
      continuation.yield(raw)
    }

    // Notify winds aloft subscribers
    for (_, (key, continuation)) in windsAloftSubscribers {
      let forecast = windsAloftForecast(for: key)
      continuation.yield(forecast)
    }
  }
}
