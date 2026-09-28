import Foundation
public import NOTAMModel

/// Reads an airport's downloaded NOTAMs and proposes values for its runway directions.
///
/// Formatted reports are read by the parsers; everything else by the on-device model when it's
/// installed (``NOTAMExtractor``). The model reads one NOTAM at a time and takes up to seconds each,
/// so readings are kept, keyed by the NOTAM, its text, and the model that read it — a NOTAM is read
/// again only when its text changes or a new model arrives.
///
/// Nothing here changes a ``NOTAM``: the proposals are for the pilot to confirm.
public actor NOTAMProposer {

  // MARK: - Instance Properties

  /// The on-device model, or `nil` when it isn't installed; asked for on every ``proposals(for:runways:)``
  /// so a model that arrives later is used.
  private let reader: @Sendable () async -> (any NOTAMReader)?

  private var readings: [ReadingKey: Result<NOTAMExtractor.Reading, NOTAMExtractor.Failure>] = [:]

  // MARK: - Initializers

  /// - Parameter reader: Supplies the on-device model, or `nil` when it isn't installed.
  public init(reader: @escaping @Sendable () async -> (any NOTAMReader)?) {
    self.reader = reader
  }

  // MARK: - Instance Methods

  /// What `notams` propose for each of `runways`.
  ///
  /// NOTAMs are read in order, and the work stops early if the task is cancelled.
  ///
  /// - Parameters:
  ///   - notams: The airport's downloaded NOTAMs.
  ///   - runways: The runway directions to propose for.
  /// - Returns: A proposal per runway direction, and the NOTAMs that couldn't be read.
  public func proposals(for notams: [NOTAMResponse], runways: [ProposalRunway]) async -> Proposals {
    let model = await reader()
    let extractor = NOTAMExtractor(reader: model)
    var proposals = Proposals(runways: runways)
    for notam in notams {
      guard !Task.isCancelled else { break }
      switch await reading(of: notam, using: extractor, modelVersion: model?.modelVersion) {
        case .success(let reading):
          proposals.add(reading, of: notam)
        case .failure(let failure):
          proposals.unreadable[notam.notamId] = failure
      }
    }
    return proposals
  }

  private func reading(
    of notam: NOTAMResponse,
    using extractor: NOTAMExtractor,
    modelVersion: String?
  ) async -> Result<NOTAMExtractor.Reading, NOTAMExtractor.Failure> {
    let key = ReadingKey(notam: notam, modelVersion: modelVersion)
    if let kept = readings[key] { return kept }
    let result: Result<NOTAMExtractor.Reading, NOTAMExtractor.Failure>
    do {
      result = .success(
        try await extractor.read(notamText: notam.notamText, location: notam.icaoLocation)
      )
    } catch {
      result = .failure(error)
    }
    if !result.isCancellation { readings[key] = result }
    return result
  }

  // MARK: - Nested Types

  /// What an airport's NOTAMs propose.
  public struct Proposals: Sendable {

    // MARK: - Instance Properties

    /// A proposal per runway direction, by the direction's name; empty proposals included.
    public private(set) var byRunway: [String: NOTAMProposal]

    /// NOTAMs that couldn't be read, by identifier, and why.
    public fileprivate(set) var unreadable: [String: NOTAMExtractor.Failure] = [:]

    private let runways: [ProposalRunway]

    // MARK: - Initializers

    init(runways: [ProposalRunway]) {
      self.runways = runways
      byRunway = Dictionary(uniqueKeysWithValues: runways.map { ($0.name, NOTAMProposal()) })
    }

    // MARK: - Instance Methods

    fileprivate mutating func add(_ reading: NOTAMExtractor.Reading, of notam: NOTAMResponse) {
      for runway in runways {
        byRunway[runway.name, default: NOTAMProposal()]
          .merge(NOTAMProposalMapper.proposal(from: reading, notamID: notam.notamId, for: runway))
      }
    }
  }

  /// Identifies one reading: the NOTAM, its text, and the model that read it.
  private struct ReadingKey: Hashable {
    let notamID: Int
    let text: String
    let modelVersion: String?

    init(notam: NOTAMResponse, modelVersion: String?) {
      notamID = notam.id
      text = notam.notamText
      self.modelVersion = modelVersion
    }
  }
}

extension Result where Failure == NOTAMExtractor.Failure {
  /// Whether the reading was cancelled, which says nothing about the NOTAM and isn't kept.
  fileprivate var isCancellation: Bool {
    if case .failure(.cancelled) = self { true } else { false }
  }
}
