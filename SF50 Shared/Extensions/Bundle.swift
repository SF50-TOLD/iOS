public import Foundation

/// A class that exists only so `Bundle(for:)` can name the bundle it was compiled into.
private final class BundleToken {}

extension Bundle {
  /**
   The bundle holding the SF50 Shared framework and the resources that ship with it, including its
   string catalog.

   Every localization API this framework calls looks in `Bundle.main` unless told otherwise, and for
   code inside a framework `Bundle.main` is whichever app loaded it — the app, the widget extension,
   or the test runner. A lookup there misses this framework's catalog and quietly hands back the key
   as its own translation, which is invisible in English because each key *is* its English text.
   Passing this bundle sends the lookup to the catalog that actually holds the strings.

   SwiftPM synthesizes a `Bundle.module` for exactly this purpose, but SF50 Shared is an Xcode
   framework target, so no such accessor exists here. Asking `Bundle(for:)` for the bundle a class
   was compiled into gets to the same place without one.
   */
  public static let sharedFramework = Bundle(for: BundleToken.self)
}

extension LocalizedStringResource.BundleDescription {
  /// ``Bundle/sharedFramework``, in the form `LocalizedStringResource` accepts.
  public static let sharedFramework = forClass(BundleToken.self)
}
