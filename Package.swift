// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Miho",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Miho", targets: ["Miho"])],
    targets: [
        .target(name: "MihoCore"),
        .executableTarget(name: "Miho", dependencies: ["MihoCore"]),
        .testTarget(name: "MihoCoreTests", dependencies: ["MihoCore"])
    ]
)
