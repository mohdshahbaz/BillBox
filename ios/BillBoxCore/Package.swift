// swift-tools-version:5.7
// BillBoxCore: the business logic of BillBox (a Swift port of the server inside the Mac app).
// The iOS app compiles these sources directly; this package exists so the logic can be built and tested on its own.
import PackageDescription

let package = Package(
    name: "BillBoxCore",
    platforms: [.iOS(.v16), .macOS(.v12)],
    products: [.library(name: "BillBoxCore", targets: ["BillBoxCore"])],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(name: "BillBoxCore", dependencies: [.target(name: "CSQLite", condition: .when(platforms: [.linux]))],
                path: "Sources/BillBoxCore"),
        .target(name: "ParityKit", dependencies: ["BillBoxCore"], path: "Sources/ParityKit"),
        .executableTarget(name: "bbcheck", dependencies: ["BillBoxCore", "ParityKit"], path: "Sources/bbcheck"),
        .testTarget(name: "BillBoxCoreTests", dependencies: ["BillBoxCore", "ParityKit"], path: "Tests/BillBoxCoreTests",
                    resources: [.copy("Golden")]),
    ]
)
