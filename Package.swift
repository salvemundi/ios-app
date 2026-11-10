// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SalveMundiCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "SalveMundiCore", targets: ["SalveMundiCore"])],
    targets: [
        .target(name: "SalveMundiCore", path: "Sources/Core"),
        .testTarget(name: "SalveMundiCoreTests", dependencies: ["SalveMundiCore"], path: "Tests/SalveMundiCoreTests")
    ]
)
