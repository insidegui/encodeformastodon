// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "encodeformastodon",
    platforms: [.macOS(.v12)],
    products: [
        .executable(
            name: "encodeformastodon",
            targets: ["encodeformastodon"]),
        .library(
            name: "VideoComposer",
            targets: ["VideoComposer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0")
    ],
    targets: [
        .target(name: "VideoComposer"),
        .executableTarget(
            name: "encodeformastodon",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .target(name: "VideoComposer"),
            ],
            linkerSettings: [
                .unsafeFlags(["-sectcreate",
                              "__TEXT",
                              "__info_plist",
                              "Sources/encodeformastodon/Resources/Info.plist"])
            ]),
    ]
)
