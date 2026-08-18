import Foundation
import SF50_Shared

/// NOTAM loader that returns no NOTAMs immediately.
///
/// Used during UI testing to eliminate network NOTAM requests. The live
/// `NOTAMLoader` reaches the NOTAM API, which is unreachable on a CI runner;
/// the in-progress request would otherwise leave the airport row spinning and
/// stall the test harness's wait-for-idle.
actor UITestingNOTAMLoader: NOTAMLoaderProtocol {
  func fetchNOTAMs(
    for _: String,
    startDate _: Date?,
    endDate _: Date?
  ) -> [NOTAMResponse] {
    []
  }
}
