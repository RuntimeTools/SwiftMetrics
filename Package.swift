import PackageDescription

let package = Package(
    name: "SwiftMetrics",
    dependencies: [
        .Package(url: "https://github.com/mattcolegate/omr-agentcore.git", majorVersion: 0)
    ]
)
