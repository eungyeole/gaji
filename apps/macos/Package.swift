// swift-tools-version: 6.2

import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let repositoryRoot = packageDirectory.deletingLastPathComponent().deletingLastPathComponent()
let rustLibraryPath = repositoryRoot.appending(path: "target/release").path

let package = Package(
    name: "RiftMac",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "RiftMac", targets: ["RiftMac"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4")
    ],
    targets: [
        .systemLibrary(name: "CRift", path: "Sources/CRift"),
        .executableTarget(
            name: "RiftMac",
            dependencies: [
                "CRift",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-force_load",
                    "-Xlinker", "\(rustLibraryPath)/librift_ffi.a"
                ])
            ]
        )
    ]
)
