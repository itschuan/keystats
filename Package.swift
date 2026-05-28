// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "keystats",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "KeystatsCore", targets: ["KeystatsCore"]),
        .executable(name: "KeystatsLite", targets: ["KeystatsLite"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(
            name: "KeystatsCore",
            dependencies: ["CSQLite"],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "KeystatsLite",
            dependencies: ["KeystatsCore"]
        ),
        .testTarget(
            name: "KeystatsCoreTests",
            dependencies: ["KeystatsCore"]
        )
    ]
)
