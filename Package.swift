// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OpenFoundationModels-Ollama",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "OpenFoundationModelsOllama",
            targets: ["OpenFoundationModelsOllama"]),
    ],
    dependencies: [
        // OpenFoundationModels core framework
        .package(url: "https://github.com/1amageek/OpenFoundationModels.git", from: "1.0.1")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "OpenFoundationModelsOllama",
            dependencies: [
                .product(name: "OpenFoundationModels", package: "OpenFoundationModels"),
                .product(name: "OpenFoundationModelsExtra", package: "OpenFoundationModels")
            ]
        ),
        .testTarget(
            name: "OpenFoundationModelsOllamaTests",
            dependencies: ["OpenFoundationModelsOllama"]
        ),
    ]
)
