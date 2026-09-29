// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Miho",
    platforms: [.macOS("14.2")],
    products: [.executable(name: "Miho", targets: ["Miho"])],
    targets: [
        .target(name: "MihoCore"),
        .target(name: "MihoDesktop", dependencies: ["MihoCore"], path: "Sources/Miho"),
        .executableTarget(name: "Miho", dependencies: ["MihoDesktop"], path: "Sources/MihoLauncher"),
        .testTarget(name: "MihoCoreTests", dependencies: ["MihoCore"]),
        .testTarget(name: "MihoDesktopTests", dependencies: ["MihoDesktop"])
    ]
)
