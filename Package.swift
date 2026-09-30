// swift-tools-version: 5.10
import PackageDescription
import Foundation

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "Miho",
    platforms: [.macOS("14.2")],
    products: [.executable(name: "Miho", targets: ["Miho"])],
    targets: [
        .target(name: "MihoCore"),
        .target(name: "CStemSeparator",cxxSettings: [.headerSearchPath("../../Vendor/onnxruntime/include")],
                linkerSettings: [.linkedLibrary("onnxruntime"),.unsafeFlags(["-L\(packageRoot)/Vendor/onnxruntime/lib",
                    "-Xlinker","-rpath","-Xlinker","@executable_path/../Frameworks",
                    "-Xlinker","-rpath","-Xlinker","\(packageRoot)/Vendor/onnxruntime/lib"])]),
        .target(name: "MihoDesktop", dependencies: ["MihoCore","CStemSeparator"], path: "Sources/Miho"),
        .executableTarget(name: "Miho", dependencies: ["MihoDesktop"], path: "Sources/MihoLauncher"),
        .testTarget(name: "MihoCoreTests", dependencies: ["MihoCore"]),
        .testTarget(name: "MihoDesktopTests", dependencies: ["MihoDesktop","CStemSeparator"])
    ],
    cxxLanguageStandard: .cxx17
)
