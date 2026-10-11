// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Freeflow",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
    ],
    targets: [
        .executableTarget(
            name: "Freeflow",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/Freeflow",
            resources: [.copy("Resources")]
        ),
    ]
)
