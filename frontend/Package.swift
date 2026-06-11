// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MHGLauncher",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "MHGLauncher", targets: ["MHGLauncher"])
    ],
    targets: [
        .executableTarget(
            name: "MHGLauncher",
            path: "Sources"
        ),
        .testTarget(
            name: "MHGLauncherTests",
            dependencies: ["MHGLauncher"],
            path: "Tests"
        )
    ]
)

