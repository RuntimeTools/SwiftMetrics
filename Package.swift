import PackageDescription

let package = Package(
    name: "SwiftMetrics",
    dependencies: [
        .Package(url: "https://github.com/IBM-Swift/CAGENTCORE.git", majorVersion: 0)
    ]
)
