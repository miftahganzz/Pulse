// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pulse",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Pulse", targets: ["Pulse"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Pulse",
            dependencies: [],
            path: "Pulse"
        ),
        .testTarget(
            name: "PulseTests",
            dependencies: ["Pulse"],
            path: "PulseTests"
        )
    ]
)
