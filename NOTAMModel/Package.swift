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
    .library(name: "NOTAMModelRuntime", targets: ["NOTAMModelRuntime"]),
    .executable(name: "notam-corpus", targets: ["NOTAMCorpus"])
  ],
  dependencies: [
    .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.3.4")
  ],
  targets: [
    .target(name: "NOTAMModel", swiftSettings: swiftSettings),
    .target(
      name: "NOTAMModelRuntime",
      dependencies: ["NOTAMModel", .product(name: "Tokenizers", package: "swift-transformers")],
      swiftSettings: swiftSettings
    ),
    .executableTarget(
      name: "NOTAMCorpus",
      dependencies: ["NOTAMModel"],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "NOTAMModelTests",
      dependencies: ["NOTAMModel"],
      swiftSettings: swiftSettings
    )
  ],
  swiftLanguageModes: [.v6]
)
