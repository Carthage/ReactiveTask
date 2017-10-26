// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "ReactiveTask",
    products: [
        .library(name: "ReactiveTask", targets: ["ReactiveTask"]),
    ],
    dependencies: [
        .package(url: "https://github.com/antitypical/Result.git", from: "3.2.1"),
        .package(url: "https://github.com/ReactiveCocoa/ReactiveSwift.git", from: "2.0.1"),
        .package(url: "https://github.com/Quick/Quick.git", from: "1.2.0"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "7.0.2"),
    ],
    targets: [
        .target(name: "ReactiveTask", dependencies: ["Result", "ReactiveSwift"], path: "Sources"),
        .testTarget(name: "ReactiveTaskTests", dependencies: ["ReactiveTask", "Quick", "Nimble"]),
    ],
    swiftLanguageVersions: [3]
)
