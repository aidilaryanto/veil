// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PilihLayar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PilihLayar", targets: ["PilihLayar"])
    ],
    targets: [
        .executableTarget(
            name: "PilihLayar",
            path: "Sources/PilihLayar"
        )
    ]
)
