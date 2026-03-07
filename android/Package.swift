// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tish88",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "Tish88",
            targets: ["Tish88"]
        )
    ],
    targets: [
        .target(
            name: "Tish88",
            dependencies: [],
            path: ".",
            exclude: ["Package.swift", "GM.sf2"],
            resources: [
                .process("GM.sf2")
            ]
        )
    ]
)


