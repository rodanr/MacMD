// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacMDKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MacMDKit", targets: ["MacMDKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "MacMDKit",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")]
        ),
        .testTarget(
            name: "MacMDKitTests",
            dependencies: ["MacMDKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
