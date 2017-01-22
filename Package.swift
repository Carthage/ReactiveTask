import PackageDescription

let package = Package(
    name: "ReactiveTask",
    dependencies: [
        .Package(url: "https://github.com/ReactiveCocoa/ReactiveSwift", majorVersion: 1),
    ]
)
