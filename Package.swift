import PackageDescription

let package = Package(
    name: "SwiftMetrics",
    targets: [
	   Target(name: "SwiftMetricsKitura", dependencies: ["SwiftMetrics"])
    ],
    dependencies: [
      .Package(url: "https://github.com/IBM-Swift/Kitura-Request.git", majorVersion: 0, minor: 6),
      .Package(url: "https://github.com/RuntimeTools/omr-agentcore.git", majorVersion: 3),
      .Package(url: "https://github.com/IBM-Swift/SwiftyJSON.git", majorVersion: 15),
      .Package(url: "https://github.com/IBM-Swift/Swift-cfenv", majorVersion: 2, minor: 0)
    ]
)
