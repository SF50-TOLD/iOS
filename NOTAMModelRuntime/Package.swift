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

// The runtime depends on NOTAMModel's product rather than sharing its package: a target dependency
// inside one package links NOTAMModel into the runtime's consumer a second time, beside the
// framework SF50 Shared links.
let package = Package(
  name: "NOTAMModelRuntime",
  platforms: [.iOS("27.0"), .macOS("27.0")],
  products: [
    .library(name: "NOTAMModelRuntime", targets: ["NOTAMModelRuntime"])
  ],
  dependencies: [
    .package(path: "../NOTAMModel"),
    .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.3.4")
  ],
  targets: [
    .target(
      name: "NOTAMModelRuntime",
      dependencies: [
        .product(name: "NOTAMModel", package: "NOTAMModel"),
        .product(name: "Tokenizers", package: "swift-transformers")
      ],
      swiftSettings: swiftSettings
    )
  ],
  swiftLanguageModes: [.v6]
)
