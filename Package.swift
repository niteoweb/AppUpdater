// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "AppUpdater",
    platforms: [.macOS(.v11)],
    products: [
        .library(name: "AppUpdater", targets: ["AppUpdater"])
    ],
    dependencies: [
        .package(url: "https://github.com/mxcl/Path.swift", from: "1.0.0"),
        .package(url: "https://github.com/ParetoSecurity/Version", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "AppUpdater",
            dependencies: [
                .product(name: "Path", package: "Path.swift"),
                .product(name: "Version", package: "Version")
            ],
            path: "Sources"
        )
    ],
    swiftLanguageVersions: [.version("5.5")]
)
