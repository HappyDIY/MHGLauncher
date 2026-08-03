// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MHGLauncher",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "MHGLauncher", targets: ["MHGLauncher"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.10.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.38.1"),
        .package(path: "Vendor/SwiftLibgit2Base")
    ],
    targets: [
        .executableTarget(
            name: "MHGLauncher",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "CLibgit2", package: "SwiftLibgit2Base"),
                "CxxHash",
                "CZstd"
            ],
            path: "Sources",
            exclude: [
                "Resources/AppIcon.icon",
                "Resources/AppIcon.icon-source",
                "Resources/Assets.xcassets",
                "Core/Sophon/sophon.proto"
            ],
            resources: [
                .process("Resources/ElementIcons"),
                .process("Resources/CoreMetadata")
            ]
        ),
        .target(
            name: "CxxHash",
            path: "Vendor/CxxHash",
            exclude: ["LICENSE"],
            publicHeadersPath: "include"
        ),
        .target(
            name: "CZstd",
            path: "Vendor/CZstd",
            exclude: ["LICENSE"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("common"),
                .headerSearchPath("decompress"),
                .define("ZSTD_MULTITHREAD", to: "0")
            ]
        ),
        .testTarget(
            name: "MHGLauncherTests",
            dependencies: ["MHGLauncher"],
            path: "Tests"
        )
    ]
)
