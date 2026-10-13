// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "fnOSApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "fnOSApp",
            targets: ["fnOSApp"]
        ),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "fnOSApp",
            path: "Sources/fnOSApp"
        ),
    ]
)
