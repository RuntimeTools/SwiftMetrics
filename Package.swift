import PackageDescription

let package = Package(
    name: "SwiftMetrics",
    dependencies: [
        .Package(url: "https://github.com/RuntimeTools/omr-agentcore.git", majorVersion: 3)
    ]
)
