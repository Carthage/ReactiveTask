// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "ReactiveTask",
    products: [
        .library(name: "ReactiveTask", targets: ["ReactiveTask"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ReactiveCocoa/ReactiveSwift.git", from: "6.0.0"),
        .package(url: "https://github.com/Quick/Quick.git", from: "2.0.0"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "8.0.1")
    ],
    targets: [
        .target(name: "ReactiveTask", dependencies: ["ReactiveSwift"], path: "Sources"),
        .testTarget(name: "ReactiveTaskTests", dependencies: ["ReactiveTask", "Quick", "Nimble"]),
    ],
    swiftLanguageVersions: [.v5]
)
