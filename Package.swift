// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PillFloat",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PillFloat",
            path: "Sources/PillFloat",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
    ]
)
