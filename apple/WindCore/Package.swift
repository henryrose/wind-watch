// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WindCore",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [
        .library(name: "WindCore", targets: ["WindCore"]),
    ],
    targets: [
        .target(
            name: "WindCore",
            resources: [.copy("Resources/payload-reference.json"), .copy("PrivacyInfo.xcprivacy")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "WindCoreTests",
            dependencies: ["WindCore"],
            resources: [.copy("Resources/payload-reference.json"), .copy("Resources/charts")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
