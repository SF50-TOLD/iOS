// swift-tools-version: 6.4

import PackageDescription

let swiftSettings: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("ImmutableWeakCaptures"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("InternalImportsByDefault"),
  .strictMemorySafety()
]

let package = Package(
  name: "NOTAMParsing",
  defaultLocalization: "en",
  platforms: [.iOS("27.0"), .macOS("27.0")],
  products: [
    .library(name: "NOTAMParsing", targets: ["NOTAMParsing"])
  ],
  targets: [
    .target(name: "NOTAMParsing", swiftSettings: swiftSettings),
    .testTarget(
      name: "NOTAMParsingTests",
      dependencies: ["NOTAMParsing"],
      swiftSettings: swiftSettings
    )
  ],
  swiftLanguageModes: [.v6]
)
