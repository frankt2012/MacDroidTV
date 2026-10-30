// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TVRemoteKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TVRemoteKit", targets: ["TVRemoteKit"])
    ],
    targets: [
        .target(
            name: "TVRemoteKit",
            path: "Sources/TVRemoteKit"
        ),
        .testTarget(
            name: "TVRemoteKitTests",
            dependencies: ["TVRemoteKit"],
            path: "Tests/TVRemoteKitTests"
        )
    ]
)
