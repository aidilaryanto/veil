// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Veil",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Veil", targets: ["Veil"])
    ],
    targets: [
        .executableTarget(
            name: "Veil",
            path: "Sources/PilihLayar"
        )
    ]
)
