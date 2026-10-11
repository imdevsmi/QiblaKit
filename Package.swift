// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QiblaKit",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "QiblaKit", targets: ["QiblaKit"])
    ],
    targets: [
        .target(name: "QiblaKit"),
        .testTarget(name: "QiblaKitTests", dependencies: ["QiblaKit"])
    ]
)
