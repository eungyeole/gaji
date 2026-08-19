// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RiftMac",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "RiftMac", targets: ["RiftMac"])],
    targets: [.executableTarget(name: "RiftMac")]
)
