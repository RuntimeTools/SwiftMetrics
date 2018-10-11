// swift-tools-version:4.2
/**
* Copyright IBM Corporation 2017
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
* http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
**/

import PackageDescription
import Foundation

var kituraNetPackage: Package.Dependency

if ProcessInfo.processInfo.environment["KITURA_NIO"] != nil {
    kituraNetPackage = .package(url: "https://github.com/IBM-Swift/Kitura-NIO.git", from: "1.0.0")
} else {
    kituraNetPackage = .package(url: "https://github.com/IBM-Swift/Kitura.git", from: "2.3.0")
}

let package = Package(
  name: "SwiftMetrics",
  products: [
        .library(
            name: "SwiftMetrics",
            targets: ["SwiftMetrics",
                "SwiftMetricsKitura",
                "SwiftBAMDC",
                "SwiftMetricsBluemix",
                "SwiftMetricsDash",
                "SwiftMetricsREST",
                "SwiftMetricsPrometheus"]),

        .executable(name: "SwiftMetricsEmitSample", targets: ["SwiftMetricsEmitSample"]),
        .executable(name: "SwiftMetricsCommonSample", targets: ["SwiftMetricsCommonSample"]),
    ],
  dependencies: [
    kituraNetPackage,
    .package(url: "https://github.com/IBM-Swift/Kitura-WebSocket.git", from: "2.0.0"),
    .package(url: "https://github.com/IBM-Swift/SwiftyRequest.git", from: "1.0.0"),
    .package(url: "https://github.com/IBM-Swift/Swift-cfenv.git", from: "6.0.0"),
    .package(url: "https://github.com/RuntimeTools/omr-agentcore", .exact("3.2.4-swift4")),
  ],
  targets: [
      .target(name: "SwiftMetrics", dependencies: ["agentcore", "hcapiplugin", "envplugin", "cpuplugin", "memplugin", "CloudFoundryEnv"]),
      .target(name: "SwiftMetricsKitura", dependencies: ["SwiftMetrics", "Kitura"]),
      .target(name: "SwiftBAMDC", dependencies: ["SwiftMetricsKitura", "SwiftyRequest", "Kitura-WebSocket"]),
      .target(name: "SwiftMetricsBluemix", dependencies: ["SwiftMetricsKitura","SwiftBAMDC"]),
      .target(name: "SwiftMetricsDash", dependencies: ["SwiftMetricsBluemix"]),
      .target(name: "SwiftMetricsREST", dependencies: ["SwiftMetricsKitura"]),
      .target(name: "SwiftMetricsPrometheus", dependencies:["SwiftMetricsKitura"]),
      .target(name: "SwiftMetricsCommonSample", dependencies: ["SwiftMetrics"],
            path: "commonSample/Sources"),
      .target(name: "SwiftMetricsEmitSample", dependencies: ["SwiftMetrics"],
            path: "emitSample/Sources"),
      .testTarget(name: "CoreSwiftMetricsTests", dependencies: ["SwiftMetrics"]),
      .testTarget(name: "SwiftMetricsRESTTests", dependencies: ["SwiftMetricsREST"])
   ]
)
