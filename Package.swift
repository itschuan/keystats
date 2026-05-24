// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "keystats",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "KeystatsCore", targets: ["KeystatsCore"]),
        .executable(name: "keystats", targets: ["keystats"])
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            pkgConfig: "sqlite3",
            providers: [
                .brew(["sqlite3"])
            ]
        ),
        .target(
            name: "KeystatsCore",
            dependencies: ["CSQLite"]
        ),
        .executableTarget(
            name: "keystats",
            dependencies: ["KeystatsCore"]
        ),
        .testTarget(
            name: "KeystatsCoreTests",
            dependencies: ["KeystatsCore"]
        ),
        .testTarget(
            name: "KeystatsCLITests",
            dependencies: ["KeystatsCore"]
        )
    ]
)

