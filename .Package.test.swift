import PackageDescription

let package = Package(
    name: "ReactiveTask",
    dependencies: [
        .Package(url: "https://github.com/ReactiveCocoa/ReactiveSwift.git", majorVersion: 1),
        .Package(url: "https://github.com/Quick/Quick.git", majorVersion: 1, minor: 1),
        .Package(url: "https://github.com/Quick/Nimble.git", majorVersion: 6),
    ]
)
