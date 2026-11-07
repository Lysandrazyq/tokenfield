// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MacQuotaAlertsHarness", platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/TokenfieldCore")], targets: [
        .target(name: "MacQuotaAlertsHarness", dependencies: [.product(name: "TokenfieldCore", package: "TokenfieldCore")], path: "Sources"),
        .testTarget(name: "MacQuotaAlertsTests", dependencies: ["MacQuotaAlertsHarness"], path: "Tests")
    ])
