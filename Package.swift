// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Voidloom",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "VoidloomCore", targets: ["VoidloomCore"])
    ],
    targets: [
        .target(name: "VoidloomCore"),
        .testTarget(
            name: "VoidloomTests",
            dependencies: ["VoidloomCore"]
        )
    ]
)
