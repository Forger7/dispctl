// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "dispctl",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "dispctl", path: "Sources/dispctl")
    ]
)
