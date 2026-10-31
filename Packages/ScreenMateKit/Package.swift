// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScreenMateKit",
    defaultLocalization: "ko",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        // Pure geometry and input logic. No networking, no UIKit.
        .library(name: "ScreenMateCore", targets: ["ScreenMateCore"]),
        // Mac Screen Sharing session wrapper around the vendored RFB engine.
        .library(name: "ScreenMateEngine", targets: ["ScreenMateEngine"]),
        // macOS command-line live check against a real Mac (login, frames,
        // monitor layout). The password is read from the terminal, never argv.
        .executable(name: "screenmate-probe", targets: ["ScreenMateProbe"]),
    ],
    dependencies: [
        // rootshell-vnc v0.1.8 (MIT), vendored with two small public-API
        // patches. See Vendor/VENDOR.md.
        .package(path: "../../Vendor/rootshell-vnc"),
    ],
    targets: [
        .target(
            name: "ScreenMateCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "ScreenMateEngine",
            dependencies: [
                "ScreenMateCore",
                .product(name: "rootshellVNC", package: "rootshell-vnc"),
                .product(name: "RFBProtocol", package: "rootshell-vnc"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "ScreenMateProbe",
            dependencies: [
                "ScreenMateCore",
                "ScreenMateEngine",
                .product(name: "rootshellVNC", package: "rootshell-vnc"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ScreenMateCoreTests",
            dependencies: ["ScreenMateCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ScreenMateEngineTests",
            dependencies: [
                "ScreenMateEngine",
                "ScreenMateCore",
                .product(name: "rootshellVNC", package: "rootshell-vnc"),
                .product(name: "RFBProtocol", package: "rootshell-vnc"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
