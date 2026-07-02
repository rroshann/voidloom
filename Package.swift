// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Voidloom",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "VoidloomCore", targets: ["VoidloomCore"]),
        .library(name: "VoidloomAI", targets: ["VoidloomAI"]),
    ],
    targets: [
        .target(name: "VoidloomCore"),
        .target(
            name: "VoidloomAI",
            dependencies: ["VoidloomCore"],
            resources: [.copy("Resources/mediator.gbnf")]
        ),
        .testTarget(
            name: "VoidloomTests",
            dependencies: ["VoidloomCore", "VoidloomAI"]
        )
    ]
)
