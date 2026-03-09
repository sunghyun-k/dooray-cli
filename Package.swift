// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "dooray-cli",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "dooray-cli",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Alamofire", package: "Alamofire"),
            ],
            path: "Sources/Dooray"
        ),
    ]
)
