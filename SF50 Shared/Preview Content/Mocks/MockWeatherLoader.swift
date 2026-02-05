import CoreLocation
import Foundation

public actor MockWeatherLoader: WeatherLoaderProtocol {

  private var mockConditions: Loadable<Conditions> = .notLoaded {
    didSet { notifyConditionsSubscribers() }
  }
  private var mockMETAR: Loadable<String?> = .notLoaded {
    didSet { notifyMETARSubscribers() }
  }
  private var mockTAF: Loadable<String?> = .notLoaded {
    didSet { notifyTAFSubscribers() }
  }
  private var mockWindsAloft: Loadable<WindsAloftData?> = .notLoaded {
    didSet { notifyWindsAloftSubscribers() }
  }
  private var mockInterpolatedEntry: WindsAloftData.Entry?
  private var mockError: Error?

  private var conditionsSubscribers = [UUID: AsyncStream<Loadable<Conditions>>.Continuation]()
  private var metarSubscribers = [UUID: AsyncStream<Loadable<String?>>.Continuation]()
  private var tafSubscribers = [UUID: AsyncStream<Loadable<String?>>.Continuation]()
  private var windsAloftSubscribers = [UUID: AsyncStream<Loadable<WindsAloftData?>>.Continuation]()

  public init(
    mockConditions: Loadable<Conditions> = .notLoaded,
    mockMETAR: Loadable<String?> = .notLoaded,
    mockTAF: Loadable<String?> = .notLoaded,
    mockWindsAloft: Loadable<WindsAloftData?> = .notLoaded,
    mockError: Error? = nil
  ) {
    self.mockConditions = mockConditions
    self.mockMETAR = mockMETAR
    self.mockTAF = mockTAF
    self.mockWindsAloft = mockWindsAloft
    self.mockError = mockError
  }

  public func setMockConditions(_ conditions: Loadable<Conditions>) {
    mockConditions = conditions
  }

  public func setMockMETAR(_ metar: Loadable<String?>) {
    mockMETAR = metar
  }

  public func setMockTAF(_ taf: Loadable<String?>) {
    mockTAF = taf
  }

  public func setMockWindsAloft(_ windsAloft: Loadable<WindsAloftData?>) {
    mockWindsAloft = windsAloft
  }

  public func setMockInterpolatedEntry(_ entry: WindsAloftData.Entry?) {
    mockInterpolatedEntry = entry
  }

  public func setMockError(_ error: Error?) {
    mockError = error
  }

  public func load(force _: Bool = false) {
    // Mock implementation - does nothing
  }

  public func cancelLoading() {
    // Mock implementation - does nothing
  }

  public func streamConditions(for _: WeatherLoader.Key) -> AsyncStream<Loadable<Conditions>> {
    let id = UUID()
    let (stream, continuation) = AsyncStream.makeStream(of: Loadable<Conditions>.self)

    conditionsSubscribers[id] = continuation
    continuation.yield(mockConditions)

    continuation.onTermination = { @Sendable [weak self] _ in
      Task { await self?.removeConditionsSubscriber(id: id) }
    }

    return stream
  }

  public func streamMETAR(for _: WeatherLoader.Key) -> AsyncStream<Loadable<String?>> {
    let id = UUID()
    let (stream, continuation) = AsyncStream.makeStream(of: Loadable<String?>.self)

    metarSubscribers[id] = continuation
    continuation.yield(mockMETAR)

    continuation.onTermination = { @Sendable [weak self] _ in
      Task { await self?.removeMETARSubscriber(id: id) }
    }

    return stream
  }

  public func streamTAF(for _: WeatherLoader.Key) -> AsyncStream<Loadable<String?>> {
    let id = UUID()
    let (stream, continuation) = AsyncStream.makeStream(of: Loadable<String?>.self)

    tafSubscribers[id] = continuation
    continuation.yield(mockTAF)

    continuation.onTermination = { @Sendable [weak self] _ in
      Task { await self?.removeTAFSubscriber(id: id) }
    }

    return stream
  }

  public func streamWindsAloft(for _: WeatherLoader.Key) -> AsyncStream<Loadable<WindsAloftData?>> {
    let id = UUID()
    let (stream, continuation) = AsyncStream.makeStream(of: Loadable<WindsAloftData?>.self)

    windsAloftSubscribers[id] = continuation
    continuation.yield(mockWindsAloft)

    continuation.onTermination = { @Sendable [weak self] _ in
      Task { await self?.removeWindsAloftSubscriber(id: id) }
    }

    return stream
  }

  public func interpolatedWindsAloft(
    at _: CLLocationCoordinate2D,
    altitude _: Measurement<UnitLength>
  ) -> WindsAloftData.Entry? {
    mockInterpolatedEntry
  }

  private func removeConditionsSubscriber(id: UUID) {
    conditionsSubscribers.removeValue(forKey: id)
  }

  private func removeMETARSubscriber(id: UUID) {
    metarSubscribers.removeValue(forKey: id)
  }

  private func removeTAFSubscriber(id: UUID) {
    tafSubscribers.removeValue(forKey: id)
  }

  private func removeWindsAloftSubscriber(id: UUID) {
    windsAloftSubscribers.removeValue(forKey: id)
  }

  private func notifyConditionsSubscribers() {
    for continuation in conditionsSubscribers.values {
      continuation.yield(mockConditions)
    }
  }

  private func notifyMETARSubscribers() {
    for continuation in metarSubscribers.values {
      continuation.yield(mockMETAR)
    }
  }

  private func notifyTAFSubscribers() {
    for continuation in tafSubscribers.values {
      continuation.yield(mockTAF)
    }
  }

  private func notifyWindsAloftSubscribers() {
    for continuation in windsAloftSubscribers.values {
      continuation.yield(mockWindsAloft)
    }
  }
}
