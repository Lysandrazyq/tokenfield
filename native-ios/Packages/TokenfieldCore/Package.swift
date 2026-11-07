// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TokenfieldCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "TokenfieldCore", targets: ["TokenfieldCore"])],
    targets: [
        .target(name: "TokenfieldCore", resources: [.process("Resources")]),
        .testTarget(name: "TokenfieldCoreTests", dependencies: ["TokenfieldCore"])
    ],
    swiftLanguageVersions: [.v5]
)
