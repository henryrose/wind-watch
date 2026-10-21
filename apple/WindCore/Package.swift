// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WindCore",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "WindCore", targets: ["WindCore"]),
    ],
    targets: [
        .target(
            name: "WindCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "WindCoreTests",
            dependencies: ["WindCore"],
            resources: [.copy("Resources/payload-reference.json")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
