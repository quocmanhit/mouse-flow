// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MouseFlow",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MouseFlow", path: "Sources/MouseFlow")
    ]
)
