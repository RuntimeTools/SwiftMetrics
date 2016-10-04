import PackageDescription

let package = Package(
    name: "commonSample",
    dependencies: [
        .Package(url: "../", versions: Version(0,0,1)..<Version(2,0,0)),
    ]
)
