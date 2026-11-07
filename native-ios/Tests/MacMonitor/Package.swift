// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MacMonitorHarness", platforms: [.macOS(.v14)], dependencies: [.package(path: "../../Packages/TokenfieldCore")], targets: [.target(name: "MacMonitorHarness", dependencies: [.product(name: "TokenfieldCore", package: "TokenfieldCore")], path: "Sources"), .testTarget(name: "MacMonitorHarnessTests", dependencies: ["MacMonitorHarness"], path: "Tests")])
