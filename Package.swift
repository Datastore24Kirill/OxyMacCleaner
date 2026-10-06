// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "OxyMacCleaner", platforms: [.macOS(.v14)],
  products: [
    .library(name: "CleanerCore", targets: ["CleanerCore"]),
    .executable(name: "OxyMacCleaner", targets: ["OxyMacCleaner"]),
  ],
  targets: [
    .target(name: "CleanerCore"),
    .executableTarget(name: "OxyMacCleaner", dependencies: ["CleanerCore"]),
    .testTarget(name: "CleanerCoreTests", dependencies: ["CleanerCore"]),
  ])
