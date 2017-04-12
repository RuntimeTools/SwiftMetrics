[![Build Status](https://travis-ci.org/RuntimeTools/SwiftMetrics.svg?branch=master)](https://travis-ci.org/RuntimeTools/SwiftMetrics)
![macOS](https://img.shields.io/badge/os-macOS-green.svg?style=flat)
![Linux](https://img.shields.io/badge/os-linux-green.svg?style=flat)
![Apache 2](https://img.shields.io/badge/license-Apache2-blue.svg?style=flat)
&nbsp;[![Slack Status](http://swift-at-ibm-slack.mybluemix.net/badge.svg)](http://swift-at-ibm-slack.mybluemix.net/)
[![Homepage](https://img.shields.io/badge/homepage-Application%20Metrics%20for%20Swift-blue.svg)](https://developer.ibm.com/swift/monitoring-diagnostics/application-metrics-for-swift)

# Application Metrics for Swift

[Application Metrics for Swift](https://developer.ibm.com/swift/monitoring-diagnostics/application-metrics-for-swift) instruments the Swift runtime for performance monitoring, providing the monitoring data programatically via an API or visually with its built in dashboard

Application Metrics for Swift provides the following built-in data collection sources:

 Source             | Description
:-------------------|:-------------------------------------------
 Environment        | Machine and runtime environment information
 CPU                | Process and system CPU
 Memory             | Process and system memory usage
 Latency            | Dispatch Queue latency

 SwiftMetricsKitura adds the additional collection source:

 Source             | Description
:-------------------|:-------------------------------------------
 HTTP               | HTTP metric information


## Getting Started
### Prerequisites

The Application Metrics for Swift agent supports the following runtime environments:

* **Swift v3 GA** on:
  * 64-bit runtime on Linux (Ubuntu 14.04, 15.10)
  * 64-bit runtime on macOS (x64)

<a name="install"></a>
### Installation
Application Metrics for Swift can be installed by adding a dependency into your Package.swift file:

```swift
dependencies: [
   .Package(url: "https://github.com/RuntimeTools/SwiftMetrics.git", majorVersion: #, minorVersion: #),
]
```

Swift Package manager will automatically clone the code required and build it during compilation of your program:
  * Linux: `swift build`
  * macOS: `swift build -Xlinker -lc++`

<a name="config"></a>
### Configuring Application Metrics for Swift
Application Metrics for Swift comes with a configuration file inside the [Packages directory](#install) (`.../Packages/SwiftMetrics-<version>/swiftmetrics.properties`). This is used to configure connection options, logging and data source options.

Application Metrics for Swift will attempt to load `swiftmetrics.properties` from one of the following locations (in order):

1. the current working directory
2. the Packages/SwiftMetrics-\<version\> directory

The default configuration has minimal logging enabled.

## Running Application Metrics for Swift
<a name="run-local"></a>
### Modifying your application

To load `SwiftMetrics` and get the base monitoring API, add the following to the start-up code for your application:
```swift
import SwiftMetrics

let sm = try SwiftMetrics()
let monitoring = sm.monitor()
```

If you would like to monitor Kitura HTTP data as well, then use the following instead:
```swift
import SwiftMetrics
import SwiftMetricsKitura

let sm = try SwiftMetrics()
SwiftMetricsKitura(swiftMetricsInstance: sm)
let monitoring = sm.monitor()
```

### Swift Metrics Dashboard

To use the built in dashboard, you add the following code to your application
```swift
import SwiftMetrics
import SwiftMetricsDash

// Enable SwiftMetrics Monitoring
let sm = try SwiftMetrics()   

// Pass SwiftMetrics to the dashboard for visualising
let smd = try SwiftMetricsDash(swiftMetricsInstance : sm)  
```
Amend Package.swift to be 
```swift
   dependencies: [
      .Package(url: "https://github.com/RuntimeTools/SwiftMetrics.git", majorVersion: #, minorVersion: #)
   ]
```

By default, SwiftMetricsDash will starts its own Kitura server and serve the page up under <hostname>:<port>/swiftmetrics-dash

The port being used is logged to the console when your application starts:

 * SwiftMetricsDash : Starting on port 8080

### Application Metrics for Swift Agent

SwiftMetrics() returns the Application Metrics for Swift Agent - this runs parallel to your code and receives and emits data about your application to any connected clients. The `sm.monitor()` call returns a Application Metrics for Swift Local Client, connected to the Agent `sm` over a local connection.

You can then use the monitoring object to register callbacks and request information about the application:
```swift
monitoring.on({ (env: InitData) in
   for (key, value) in env {
      print("\(key): \(value)\n")
   }
})

func processCPU(cpu: CPUData) {
   print("\nThis is a custom CPU event response.\n cpu.timeOfSample = \(cpu.timeOfSample),\n cpu.percentUsedByApplication = \(cpu.percentUsedByApplication),\n cpu.percentUsedBySystem = \(cpu.percentUsedBySystem).\n")
}

monitoring.on(processCPU)
```

In order to monitor your own custom data, you need to implement a struct that implements the base SwiftMetrics data protocol, SMData. This has no required fields so you can put in just the data you're interested in.
```swift
private struct SnoozeData: SMData {
   let cycleCount: Int
}

private func snoozeMessage(data: SnoozeData) {
   print("\nAlarm has been ignored for \(data.cycleCount) seconds!\n")
}

monitoring.on(snoozeMessage)

sm.emitData(SnoozeData(cycleCount: 40))

//prints "Alarm has been ignored for 40 seconds!"
```

<a name="api-doc"></a>
## API Documentation

### SwiftMetrics.start()
Starts the Application Metrics for Swift Agent. If the agent is already running this function does nothing.

### SwiftMetrics.stop()
Stops the Application Metrics for Swift Agent. If the agent is not running this function does nothing.

### SwiftMetrics.setPluginSearch(toDirectory: URL)
Sets the directory that Application Metrics for Swift will look in for data source / connector plugins.

### SwiftMetrics.monitor() -> SwiftMonitor
Creates a Application Metrics for Swift Local Client instance, connected to the Application Metrics for Swift Agent specified by 'SwiftMetrics'. This can subsequently be used to get environment data and subscribe to data generated by the Agent.. This function will start the Application Metrics for Swift Agent if it is not already running.

### SwiftMetrics.emitData<T: SMData( _: T)
Allows you to emit custom Data specifying the type of Data as a string. Data to pass into the event must implement the SMData protocol.

### SwiftMonitor.getEnvironmentData() -> [ String : String ]
Requests a Dictionary object containing all of the available environment information for the running application. If called before the 'initialized' event has been emitted, this will contain either incomplete data or no data.

### SwiftMonitor.on<T: SMData>((T) -> ())
If you supply a closure that takes either a *[pre-supplied API struct](#api-structs)* or your own custom struct that implements the SMData protocol,  and returns nothing, then that closure will run when the data in question is emitted.

### SwiftMetricsKitura(swiftMetricsInstance: SwiftMetrics) (when importing SwiftMetricsKitura)
Creates a SwiftMetricsKitura instance, which will monitor Kitura HTTP metrics and emit them via the SwiftMetrics instance specified.

### SwiftMetricsBluemix(swiftMetricsInstance: SwiftMetrics) (when importing SwiftMetricsBluemix)
Creates a SwiftMetricsBluemix instance, which will send metrics to the [Auto Scale service][4]

<a name="api-structs"></a>
## API Data Structures

All of the following structures implement the SMData protocol to identify them as available to be used by SwiftMetrics.
```swift
public protocol SMData {
}
```

### CPU data structure
Emitted when a CPU monitoring sample is taken.
* `public struct CPUData: SMData`
    * `timeOfSample` (Int) the system time in milliseconds since epoch when the sample was taken.
    * `percentUsedByApplication` (Float) the percentage of CPU used by the Swift application itself. This is a value between 0.0 and 1.0.
    * `percentUsedBySystem` (Float) the percentage of CPU used by the system as a whole. This is a value between 0.0 and 1.0.

### Memory data structure
Emitted when a memory monitoring sample is taken.
* `public struct MemData: SMData`
    * `timeOfSample` (Int) the system time in milliseconds since epoch when the sample was taken.
    * `totalRAMOnSystem` (Int) the total amount of RAM available on the system in bytes.
    * `totalRAMUsed` (Int) the total amount of RAM in use on the system in bytes.
    * `totalRAMFree` (Int) the total amount of free RAM available on the system in bytes.
    * `applicationAddressSpaceSize` (Int) the memory address space used by the Swift application in bytes.
    * `applicationPrivateSize` (Int) the amount of memory used by the Swift application that cannot be shared with other processes, in bytes.
    * `applicationRAMUsed` (Int) the amount of RAM used by the Swift application in bytes.

### HTTP data structure (when including SwiftMetricsKitura)
Emitted when an HTTP monitoring sample is taken.
* `public struct HTTPData: SMData`
    * `timeOfRequest` (Int) the system time in milliseconds since epoch when the request was made.
    * `url` (String) the request url.
    * `duration` (Double) the duration the request took.
    * `statusCode` (HTTPStatusCode) the HTTP status code of the request.
    * `requestMethod` (String) the method {GET SET} of the request.

### Initialized data structure
Emitted when all expected environment samples have been received, signalling a complete set of environment variables is available for SwiftMonitor.getEnvironmentData().
* `public struct InitData: SMData`
    * `data` ([String: String] Dictionary) of environment variable name:value pairs. The contents vary depending on system.

### Environment data structure
Emitted when an environment sample is taken. The Dictionary obtained with this data may not represent the complete set of environment variables.
* `public struct EnvData: SMData`
    * `data` ([String: String] Dictionary) of environment variable name:value pairs. The contents vary depending on system.

### Latency data structure
Emitted when a Latency sample is taken.
* `public struct LatencyData: SMData`
    * `timeOfSample` (Int) the system time in milliseconds since epoch when the sample was taken.
    * `duration` (Double) the duration the sample waited in the dispatch queue to be executed.

## Samples

There are two samples available:
* `commonSample` demonstrates how to get data from the common data types, using the API.
* `emitSample` demonstrates the use of Custom Data emission and collection.

To use either, navigate to their directory and issue `swift build` (on macOS, `swift build -Xlinker -lc++`)

## Troubleshooting
Find below some possible problem scenarios and corresponding diagnostic steps. Updates to troubleshooting information will be made available on the [SwiftMetrics wiki][1]: [Troubleshooting](https://github.com/RuntimeTools/SwiftMetrics/wiki/Troubleshooting). If these resources do not help you resolve the issue, you can open an issue on the Application Metrics for Swift [issue tracker][2].

### Checking Application Metrics for Swift has started
By default, a message similar to the following will be written to console output when Application Metrics for Swift starts:

`[Fri Aug 21 09:36:58 2015] com.ibm.diagnostics.healthcenter.loader INFO: Swift Application Metrics 1.0.1-201508210934 (Agent Core 3.0.5.201508210934)`

### Error "Failed to open library .../libagentcore.so: /usr/lib64/libstdc++.so.6: version `GLIBCXX_3.4.15' not found"
This error indicates there was a problem while loading the native part of the module or one of its dependent libraries. `libagentcore.so` depends on a particular (minimum) version of the C runtime library and if it cannot be found this error is the result.

Check:

* Your system has the required version of `libstdc++` installed. You may need to install or update a package in your package manager. If your OS does not supply a package at this version, you may have to install standalone software - consult the documentation or support forums for your OS.
* If you have an appropriate version of `libstdc++`installed, ensure it is on the system library path, or use a method (such as setting `LD_LIBRARY_PATH` environment variable on Linux) to add the library to the search path.

## Source code
The source code for Application Metrics for Swift is available in the [Swiftmetrics project][3]. Information on working with the source code -- installing from source, developing, contributing -- is available on the [SwiftMetrics wiki][1].

## License
This project is released under an Apache 2.0 open source license.  

## Versioning scheme
This project uses a semver-parsable X.0.Z version number for releases, where X is incremented for breaking changes to the public API described in this document and Z is incremented for bug fixes **and** for non-breaking changes to the public API that provide new function.

### Development versions
Non-release versions of this project (for example on github.com/RuntimeTools/SwiftMetrics) will use semver-parsable X.0.Z-dev.B version numbers, where X.0.Z is the last release with Z incremented and B is an integer. For further information on the development process go to the  [SwiftMetrics wiki][1]: [Developing](https://github.com/RuntimeTools/SwiftMetrics/wiki/Developing).

## Version
1.0.2

## Release History
`1.0.2` - Initial Swift 3.1 support (SwiftMetricsDash not working on 3.1).  
`1.0.0` - First GA release.  
`0.0.12` - BlueMix AutoScaling support.  
`0.0.11` - BlueMix support.  
`0.0.10` - Addition of Kitura HTTP collection source.  
`0.0.9` - Initial development release.  


[1]: https://github.com/RuntimeTools/SwiftMetrics/wiki
[2]: https://github.com/RuntimeTools/SwiftMetrics/issues
[3]: https://github.com/RuntimeTools/SwiftMetrics
[4]: https://www.ibm.com/cloud-computing/bluemix/auto-scale
