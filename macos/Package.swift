// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DistributorPro",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(name: "DistributorPro", path: "Sources/DistributorPro")
    ]
)
