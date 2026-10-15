// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacMDKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MacMDKit", targets: ["MacMDKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.9.0"),
        // Already used by swift-markdown; the tests use its reference HTML renderer to check ours.
        .package(url: "https://github.com/swiftlang/swift-cmark.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "MacMDKit",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")]
        ),
        .testTarget(
            name: "MacMDKitTests",
            dependencies: [
                "MacMDKit",
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ]
)
