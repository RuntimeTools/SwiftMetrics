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

#if os(Linux)
   let excludePortDir = "Sources/agentcore/ibmras/common/port/osx"
#else
   let excludePortDir = "Sources/agentcore/ibmras/common/port/linux"
#endif

let package = Package(
  name: "SwiftMetrics",
  targets: [
      Target(name: "SwiftMetrics", dependencies: [.Target(name: "agentcore"),
                                                   .Target(name: "cpuplugin"),
                                                   .Target(name: "envplugin"),
                                                   .Target(name: "memplugin"),
                                                   .Target(name: "hcapiplugin")]),
      Target(name: "SwiftMetricsKitura", dependencies: ["SwiftMetrics"]),
      Target(name: "SwiftBAMDC", dependencies: ["SwiftMetricsKitura"]),
      Target(name: "SwiftMetricsBluemix", dependencies: ["SwiftMetricsKitura","SwiftBAMDC"]),
      Target(name: "SwiftMetricsDash", dependencies: ["SwiftMetricsBluemix"]),
      Target(name: "mqttplugin", dependencies: [.Target(name: "paho"),
                                                   .Target(name: "agentcore")]),
      Target(name: "cpuplugin", dependencies: [.Target(name: "agentcore")]),
      Target(name: "envplugin", dependencies: [.Target(name: "agentcore")]),
      Target(name: "memplugin", dependencies: [.Target(name: "agentcore")]),
      Target(name: "hcapiplugin", dependencies: [.Target(name: "agentcore")])
   ],
  dependencies: [
    .Package(url: "https://github.com/IBM-Swift/Kitura.git", majorVersion: 1, minor: 6),
    .Package(url: "https://github.com/IBM-Swift/Kitura-WebSocket.git", majorVersion: 0, minor: 7),
    .Package(url: "https://github.com/IBM-Swift/Kitura-Request.git", majorVersion: 0, minor: 7),
    .Package(url: "https://github.com/IBM-Swift/CloudConfiguration.git", majorVersion: 1)
  ],
   exclude: [ "Sources/agentcore/ibmras/common/port/aix",
              "Sources/agentcore/ibmras/common/port/windows",
              "Sources/agentcore/ibmras/common/data",
              "Sources/agentcore/ibmras/common/util/memUtils.cpp",
              "Sources/ostreamplugin",
              "Sources/paho/Windows Build",
              "Sources/paho/build",
              "Sources/paho/doc",
              "Sources/paho/test",
              "Sources/paho/src/MQTTClient.c",
              "Sources/paho/src/MQTTVersion.c",
              "Sources/paho/src/SSLSocket.c",
              "Sources/paho/src/samples",
              excludePortDir
   ]
)

