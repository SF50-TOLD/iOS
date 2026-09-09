public import Foundation

import Defaults
import SwiftData
import os

/// Switches the app to a newly written generation of the nav-data store.
///
/// Installing is a single `Defaults` write, and it happens only after the candidate has been opened
/// and found to hold a dataset. Nothing is overwritten and nothing is deleted, so an import that
/// fails — or is killed mid-flight when the pilot swipes the app away — leaves the dataset in use
/// exactly as it was.
public struct NavDataStoreInstaller: Sendable {
  private static let logger = Logger(
    subsystem: "codes.tim.SF50-TOLD",
    category: "NavDataStoreInstaller"
  )

  private let layout: StoreLayout

  /// The generation currently in use.
  public var activeGeneration: Int { Defaults[.activeNavDataGeneration] }

  /// Creates an installer for the stores `layout` arranges.
  ///
  /// - Parameter layout: Where the stores live.
  public init(layout: StoreLayout) {
    self.layout = layout
  }

  /// A generation number no store is using, for an import to write.
  ///
  /// Numbers rise rather than alternate, so a generation an extension still has open is never
  /// reused underneath it.
  public func reserveGeneration() -> Int {
    let next = max(activeGeneration, layout.navStoreGenerations().max() ?? 0) + 1
    StoreLayout.removeStore(at: layout.navStoreURL(generation: next))
    return next
  }

  /// Switches to `generation`, if the store it names holds a usable dataset.
  ///
  /// - Parameter generation: The generation an import has just written.
  /// - Throws: ``Errors/storeIsEmpty`` if the candidate holds no airports,
  ///   ``AppStore/Errors/navDataStoreIsMissing(generation:)`` if its store has gone from disk, or
  ///   the error SwiftData raised trying to open it.
  public func install(generation: Int) throws {
    try validate(generation: generation)
    Defaults[.activeNavDataGeneration] = generation
    Self.logger.notice("Switched to nav-data generation \(generation, privacy: .public)")
  }

  /// Opens a candidate generation and confirms it holds a dataset.
  ///
  /// Opening it here, through the same configurations the app uses, is what turns a store this
  /// binary cannot read into a failed install rather than a broken launch. It is opened as a
  /// generation that must already be on disk: a candidate an extension's launch-time sweep
  /// reclaimed between reserving it and installing it is a store that has gone, and bootstrapping
  /// an empty one in its place would refuse the install for the wrong reason and leave a file
  /// behind that nothing wrote.
  ///
  /// - Parameter generation: The generation to check.
  private func validate(generation: Int) throws {
    let container = try AppStore.makeContainerForExistingGeneration(
      layout: layout,
      generation: generation
    )
    let context = ModelContext(container)
    guard try context.fetchCount(FetchDescriptor<Airport>()) > 0 else {
      throw Errors.storeIsEmpty
    }
  }

  /// Reasons a candidate store was refused.
  public enum Errors: Swift.Error, LocalizedError {
    /// The store held no airports.
    case storeIsEmpty

    public var errorDescription: String? {
      String(
        localized: "Couldn’t use the navigation data that was downloaded.",
        bundle: .sharedFramework
      )
    }

    public var failureReason: String? {
      switch self {
        case .storeIsEmpty:
          String(
            localized: "The downloaded database contained no airports.",
            bundle: .sharedFramework
          )
      }
    }

    public var recoverySuggestion: String? {
      String(localized: "Try downloading the navigation data again.", bundle: .sharedFramework)
    }
  }
}
