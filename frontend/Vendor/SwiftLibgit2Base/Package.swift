// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "swift-libgit2-base",
    platforms: [.macOS(.v13)],
    products: [.library(name: "CLibgit2", targets: ["CLibgit2"])],
    targets: [
        .target(
            name: "CLibgit2",
            dependencies: ["libgit2", "libssh2", "libssl", "libcrypto"]
        ),
        .binaryTarget(name: "libgit2", path: "lib/libgit2.zip"),
        .binaryTarget(name: "libssh2", path: "lib/libssh2.zip"),
        .binaryTarget(name: "libssl", path: "lib/libssl.zip"),
        .binaryTarget(name: "libcrypto", path: "lib/libcrypto.zip")
    ]
)
