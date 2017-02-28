import PackageDescription

let package = Package(
    name: "ReactiveTask",
    dependencies: [
        .Package(url: "https://github.com/ReactiveCocoa/ReactiveSwift.git", versions: Version(1, 1, 0)..<Version(1, .max, .max)),
        .Package(url: "https://github.com/Quick/Quick.git", majorVersion: 1, minor: 1),
        .Package(url: "https://github.com/Quick/Nimble.git", majorVersion: 6),
    ]
)
