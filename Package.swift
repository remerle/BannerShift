// swift-tools-version:5.10
import PackageDescription

// swift-testing is added as an explicit SwiftPM dependency so the test
// target compiles on machines with only Command Line Tools (no full
// Xcode installed). With Xcode present, Swift 6's toolchain-bundled
// Testing module is preferred and the dependency can be removed; until
// then this is the portable path.
let package = Package(
  name: "BannerShift",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "BannerShift", targets: ["BannerShift"]),
    .library(name: "BannerShiftCore", targets: ["BannerShiftCore"]),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.10.0"),
    // SwiftLint command plugin. Invoke via `swift package plugin swiftlint` or
    // through the Makefile `lint` target. Build-tool plugin is intentionally
    // not attached to targets so the inner-loop `swift build` stays fast.
    .package(url: "https://github.com/realm/SwiftLint.git", from: "0.55.0"),
  ],
  targets: [
    .target(name: "BannerShiftCore"),
    .executableTarget(
      name: "BannerShift",
      dependencies: ["BannerShiftCore"]
    ),
    .testTarget(
      name: "BannerShiftCoreTests",
      dependencies: [
        "BannerShiftCore",
        .product(name: "Testing", package: "swift-testing"),
      ]
    ),
  ]
)
