// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CodeEditorUI",
    platforms: [.iOS(.v17)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "CodeEditorUI",
            targets: ["CodeEditorUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/xibbon/RunestoneUI", branch: "main"),
        .package(url: "https://github.com/xibbon/Runestone", branch: "main"),
        .package(url: "https://github.com/xibbon/MiniTreeSitterLanguages", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "CodeEditorUI",
            dependencies: [
                "RunestoneUI",
                "Runestone",
                .product(name: "TreeSitterGDScriptRunestone", package: "MiniTreeSitterLanguages"),
                .product(name: "TreeSitterJSON", package: "MiniTreeSitterLanguages"),
                .product(name: "TreeSitterJSONRunestone", package: "MiniTreeSitterLanguages"),
                .product(name: "TreeSitterMarkdownRunestone", package: "MiniTreeSitterLanguages"),
                .product(name: "TreeSitterGLSLRunestone", package: "MiniTreeSitterLanguages"),
            ]),
        .testTarget(
            name: "CodeEditorUITests",
            dependencies: ["CodeEditorUI"]),
    ]
)
