// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Voidloom",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Voidloom", targets: ["Voidloom"]),
        .library(name: "VoidloomCore", targets: ["VoidloomCore"])
    ],
    targets: [
        .target(name: "VoidloomCore"),
        .executableTarget(
            name: "Voidloom",
            dependencies: ["VoidloomCore"]
        ),
        .testTarget(
            name: "VoidloomTests",
            dependencies: ["VoidloomCore"]
        )
    ]
)
