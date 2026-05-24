// swift-tools-version:5.10
import PackageDescription

// Tests use the swift-testing framework bundled with the Swift 6 toolchain
// (`import Testing`), so no external swift-testing package dependency is
// declared. Requires a Swift 6.0+ toolchain (Xcode 16+ or matching Command
// Line Tools), which ships the Testing module and its macros.
let package = Package(
  name: "BannerShift",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "BannerShift", targets: ["BannerShift"]),
    .library(name: "BannerShiftCore", targets: ["BannerShiftCore"]),
  ],
  dependencies: [
    // SwiftLint command plugin. Invoke via `swift package plugin swiftlint` or
    // through the Makefile `lint` target. Build-tool plugin is intentionally
    // not attached to targets so the inner-loop `swift build` stays fast.
    .package(url: "https://github.com/realm/SwiftLint.git", from: "0.55.0")
  ],
  targets: [
    .target(name: "BannerShiftCore"),
    .executableTarget(
      name: "BannerShift",
      dependencies: ["BannerShiftCore"]
    ),
    .testTarget(
      name: "BannerShiftCoreTests",
      dependencies: ["BannerShiftCore"]
    ),
  ]
)
