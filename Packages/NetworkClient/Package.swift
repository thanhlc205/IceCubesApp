// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "NetworkClient",
  defaultLocalization: "en",
  platforms: [
    .iOS(.v18),
    .visionOS(.v1),
  ],
  products: [
    .library(
      name: "NetworkClient",
      targets: ["NetworkClient"]
    ),
    // Test helpers that answer or fail `URLSession.shared` requests. Link it only from tests.
    .library(
      name: "NetworkStubs",
      targets: ["NetworkStubs"]
    ),
  ],
  dependencies: [
    .package(name: "Models", path: "../Models")
  ],
  targets: [
    .target(
      name: "NetworkClient",
      dependencies: [
        .product(name: "Models", package: "Models")
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
    .target(
      name: "NetworkStubs",
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
    .testTarget(
      name: "NetworkClientTests",
      dependencies: ["NetworkClient", "NetworkStubs"]
    ),
  ]
)
