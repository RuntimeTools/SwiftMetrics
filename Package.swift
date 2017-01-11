import PackageDescription

let package = Package(
    name: "SwiftMetrics",
    targets: [
	Target(name: "SwiftMetricsKitura", dependencies: ["SwiftMetrics"]),
        Target(name: "SwiftBluemixAutoScalingAgent", dependencies: ["SwiftMetricsKitura"])
    ],
    dependencies: [
      .Package(url: "https://github.com/IBM-Swift/Kitura-Request.git", majorVersion: 0),
      .Package(url: "https://github.com/RuntimeTools/omr-agentcore.git", majorVersion: 3),
      .Package(url: "https://github.com/IBM-Swift/SwiftyJSON.git", majorVersion: 15),
      .Package(url: "https://github.com/IBM-Bluemix/cf-deployment-tracker-client-swift.git", majorVersion: 0) 
    ]
)
