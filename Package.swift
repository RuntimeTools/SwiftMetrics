import PackageDescription

let package = Package(
    name: "SwiftMetrics",
    targets: [
        Target(name: "SwiftMetricsKitura", dependencies: ["SwiftMetrics"])
    ],
    dependencies: [
        .Package(url: "https://github.com/RuntimeTools/omr-agentcore.git", majorVersion: 3),
        .Package(url: "https://github.com/IBM-Swift/Kitura-net.git", majorVersion: 1, minor: 3)
    ]
)

