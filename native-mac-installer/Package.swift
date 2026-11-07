// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TokenfieldInstaller",
    platforms: [.macOS(.v14)],
    products: [.library(name: "InstallerCore", targets: ["InstallerCore"])],
    targets: [
        .target(name: "InstallerCore"),
        .testTarget(name: "InstallerCoreTests", dependencies: ["InstallerCore"])
    ]
)
