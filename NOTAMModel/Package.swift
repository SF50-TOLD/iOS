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
  name: "NOTAMModel",
  defaultLocalization: "en",
  platforms: [.iOS("27.0"), .macOS("27.0")],
  products: [
    .library(name: "NOTAMModel", targets: ["NOTAMModel"]),
    .executable(name: "notam-corpus", targets: ["NOTAMCorpus"])
  ],
  dependencies: [.package(path: "../NOTAMParsing")],
  targets: [
    .target(
      name: "NOTAMModel",
      dependencies: ["NOTAMParsing"],
      swiftSettings: swiftSettings
    ),
    .executableTarget(
      name: "NOTAMCorpus",
      dependencies: ["NOTAMModel", "NOTAMParsing"],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "NOTAMModelTests",
      dependencies: ["NOTAMModel", "NOTAMParsing"],
      exclude: ["Fixtures"],
      swiftSettings: swiftSettings
    )
  ],
  swiftLanguageModes: [.v6]
)
