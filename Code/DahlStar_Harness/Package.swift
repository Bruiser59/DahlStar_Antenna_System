// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DahlStarHarness",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DahlStarHarness",
            path: "Sources/DahlStarHarness",
            swiftSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate",
                              "-Xlinker", "__TEXT",
                              "-Xlinker", "__entitlements",
                              "-Xlinker", "DahlStarHarness.entitlements"])
            ]
        )
    ]
)
