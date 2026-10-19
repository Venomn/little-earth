// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LittleEarth",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LittleEarth", targets: ["LittleEarth"])],
    targets: [
        .target(name: "EarthCore", resources: [.copy("Resources")]),
        .executableTarget(name: "LittleEarth", dependencies: ["EarthCore"], resources: [.copy("Resources")]),
        .testTarget(name: "EarthCoreTests", dependencies: ["EarthCore"]),
        .testTarget(name: "LittleEarthTests", dependencies: ["LittleEarth"])
    ]
)
