import PackageDescription

let package = Package(
  name: "SwiftMetrics",
  targets: [
      Target(name: "SwiftMetricsKitura", dependencies: ["SwiftMetrics"]),
      Target(name: "SwiftMetricsBluemix", dependencies: ["SwiftMetricsKitura"]),
      Target(name: "SwiftMetricsDash", dependencies: ["SwiftMetricsBluemix"])
    ],
  dependencies: [
    .Package(url: "https://github.com/RuntimeTools/omr-agentcore.git", majorVersion: 3),
    .Package(url: "https://github.com/IBM-Swift/Kitura.git", majorVersion: 1, minor: 6),
    .Package(url: "https://github.com/IBM-Swift/Kitura-Request.git", majorVersion: 0, minor: 7),
    .Package(url: "https://github.com/IBM-Swift/CloudConfiguration.git", majorVersion: 1)
  ]
)
