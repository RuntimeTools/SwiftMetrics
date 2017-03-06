import PackageDescription

let package = Package(
    name: "emitSample",
    dependencies: [
        .Package(url: "https://github.com/RuntimeTools/SwiftMetrics.git", versions: Version(0,0,1)..<Version(2,0,0)),
    ]
)
