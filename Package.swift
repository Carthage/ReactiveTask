// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "ReactiveTask",
    products: [
        .library(name: "ReactiveTask", targets: ["ReactiveTask"])
    ],
    dependencies: [
        .package(url: "https://github.com/antitypical/Result.git", from: "4.0.0"),
        .package(url: "https://github.com/ReactiveCocoa/ReactiveSwift.git", from: "4.0.0"),
        .package(url: "https://github.com/Quick/Quick.git", from: "1.3.1"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "7.1.3")
    ],
    targets: [
        .target(name: "ReactiveTask", dependencies: ["Result", "ReactiveSwift"], path: "Sources"),
        .testTarget(name: "ReactiveTaskTests", dependencies: ["ReactiveTask", "Quick", "Nimble"])
    ],
    swiftLanguageVersions: [4]
)
