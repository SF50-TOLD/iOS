import Foundation

/// Which networks a nav-data download may use.
///
/// A pilot who starts an update has chosen to spend the data, whatever network they are on. An update
/// the system starts in the background has not been asked for, so it keeps to networks iOS does not
/// treat as metered unless the pilot has allowed it.
///
/// Whether a network is metered is iOS's call, made from the pilot's own settings rather than from
/// the kind of network. Cellular in the Standard data mode and a personal hotspot are expensive;
/// Low Data Mode, on any network, is constrained. 5G with Allow More Data is neither: the pilot has
/// told iOS to treat it like Wi-Fi, and this follows them.
enum NavDataNetworkAccess: Sendable {
  /// Any network the device has.
  case any

  /// Networks iOS treats as neither expensive nor constrained.
  case unmeteredOnly

  /// The session configuration a download under this policy runs on.
  var sessionConfiguration: URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.allowsExpensiveNetworkAccess = self == .any
    configuration.allowsConstrainedNetworkAccess = self == .any
    return configuration
  }

  /// Whether `error` is a download this policy refused, rather than one that failed.
  ///
  /// A refusal says nothing is wrong: the device is on a network the update was told not to use. It
  /// is neither worth retrying nor worth reporting.
  static func isRefusal(_ error: any Error) -> Bool {
    (error as? URLError)?.networkUnavailableReason != nil
  }
}
