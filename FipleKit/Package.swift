// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FipleKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "FipleKit", targets: ["FipleKit"])
    ],
    targets: [
        .target(
            name: "FipleKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FipleKitTests",
            dependencies: ["FipleKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
