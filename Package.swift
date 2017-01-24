import PackageDescription

let package = Package(
  name: "SwiftMetrics",
  dependencies: [
    .Package(url: "https://github.com/RuntimeTools/omr-agentcore.git", majorVersion: 3),
    .Package(url: "https://github.com/IBM-Swift/Swift-cfenv.git", majorVersion: 2, minor: 0)
  ]
)
