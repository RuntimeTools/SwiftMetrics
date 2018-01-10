/*******************************************************************************
 * Copyright 2017 IBM Corp.
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
 *******************************************************************************/
import agentcore
import Foundation
import Dispatch
import Configuration
import CloudFoundryEnv
#if os(Linux)
import Glibc
#else
import Darwin
#endif

public protocol SMData: Encodable {
}

public struct CPUData: SMData {
  public let timeOfSample: Int
  public let percentUsedByApplication: Float
  public let percentUsedBySystem: Float

  enum CodingKeys: String, CodingKey {
    case timeOfSample = "time"
    case percentUsedByApplication = "process"
    case percentUsedBySystem = "system"
  }
}

public struct MemData: SMData {
  public let timeOfSample: Int
  public let totalRAMOnSystem: Int
  public let totalRAMUsed: Int
  public let totalRAMFree: Int
  public let applicationAddressSpaceSize: Int
  public let applicationPrivateSize: Int
  public let applicationRAMUsed: Int

  enum CodingKeys: String, CodingKey {
    case timeOfSample = "time"
    case applicationRAMUsed = "physical"
    case totalRAMUsed = "physical_used"
  }
}

public struct EnvData: SMData {
  public let data: [String:String]
}

public struct InitData: SMData {
  public let data: [String:String]
}

public struct LatencyData: SMData {
  public let timeOfSample: Int
  public let duration: Double
}

public var swiftMon: SwiftMonitor?

private var initialized = false;
private func receiveAgentCoreData(cSourceId: UnsafePointer<CChar>, cSize: CUnsignedInt, data: UnsafeMutableRawPointer) -> Void {
  let size = Int(cSize)
  if size <= 0 {
    return
  }
  let source = String(cString: cSourceId)
  if source != "api" {
    let opaquePointer = OpaquePointer(data)
    let cstrPointer = UnsafePointer<CChar>(opaquePointer)

    let message = String(cString:cstrPointer)
    if swiftMon != nil {
      swiftMon!.raiseCoreEvent(topic: source, message: message)
    }
  }
}

open class SwiftMetrics {

  let loaderApi: loaderCoreFunctions
  let CLOUD_LIBRARY_PATH = "/home/vcap/app/.swift-lib"
  let SWIFTMETRICS_VERSION = "99.99.99.29991231"
  var running = false
  typealias monitorPushData = @convention(c) (UnsafePointer<CChar>) -> Void
  typealias monitorSendControl = @convention(c) (UnsafePointer<CChar>, CUnsignedInt, UnsafeMutableRawPointer) -> Void
  typealias monitorRegisterListener = @convention(c) (monitorSendControl) -> Void
  var pushData: monitorPushData?
  var sendControl: monitorSendControl?
  var registerListener: monitorRegisterListener?
  var sleepInterval: UInt32 = 2
  var latencyEnabled: Bool = false
  let jobsQueue = DispatchQueue(label: "Swift Metrics Jobs Queue")
  let isRunningOnCloud: Bool
  public let localSourceDirectory: String

  public init() throws {
    self.loaderApi = loader_entrypoint().pointee
    //find the SwiftMetrics directory where swiftmetrics.properties and SwiftMetricsDash public folder are
    let fm = FileManager.default
    let currentDir = fm.currentDirectoryPath
    let configMgr = ConfigurationManager().load(.environmentVariables)
    self.isRunningOnCloud = !configMgr.isLocal

    var applicationPath = ""
    if configMgr.isLocal {
      var workingPath = ""
      if currentDir.contains(".build") {
        ///we're below the Packages directory
        workingPath = currentDir
      } else {
        ///we're above the Packages directory
        workingPath = CommandLine.arguments[0]
      }
      if let i = workingPath.range(of: ".build") {
        applicationPath = String(workingPath[..<i.lowerBound])
      } else {
        print("SwiftMetrics: Error finding .build directory")
      }
    } else {
      // We're in Bluemix, use the path the swift-buildpack saves libraries to
      applicationPath = "/home/vcap/app/"
    }

    // Swift 3.1
    let checkoutsPath = applicationPath + ".build/checkouts/"
    if fm.fileExists(atPath: checkoutsPath) {
      _ = fm.changeCurrentDirectoryPath(checkoutsPath)
    } else { // Swift 3.0
      let packagesPath = applicationPath + "Packages/"
      if fm.fileExists(atPath: packagesPath) {
        _ = fm.changeCurrentDirectoryPath(packagesPath)
      } else {
        print("SwiftMetrics: Error finding directory containing source code in \(applicationPath)")
      }
    }
    do {
      let dirContents = try fm.contentsOfDirectory(atPath: fm.currentDirectoryPath)
      for dir in dirContents {
        if dir.contains("SwiftMetrics") {
          ///that's where we want to be!
          _ = fm.changeCurrentDirectoryPath(dir)
        }
      }
    } catch {
      print("SwiftMetrics: Error obtaining contents of directory: \(fm.currentDirectoryPath), \(error).")
      throw error
    }
    let propertiesPath = "\(fm.currentDirectoryPath)/swiftmetrics.properties"
    if fm.fileExists(atPath: propertiesPath) {
      self.localSourceDirectory = fm.currentDirectoryPath
    } else {
        // could be in Xcode, try source directory
        let fileName = NSString(string: #file)
        let installDirPrefixRange: NSRange
        let installDir = fileName.range(of: "/Sources/SwiftMetrics/SwiftMetrics.swift", options: .backwards)
        if  installDir.location != NSNotFound {
          installDirPrefixRange = NSRange(location: 0, length: installDir.location)
        } else {
          installDirPrefixRange = NSRange(location: 0, length: fileName.length)
        }
        let folderName = fileName.substring(with: installDirPrefixRange)
        self.localSourceDirectory = folderName
    }
    _ = fm.changeCurrentDirectoryPath(currentDir)
    try self.loadProperties()
    loaderApi.setLogLevels()
    loaderApi.setProperty("agentcore.version", loaderApi.getAgentVersion())
    loaderApi.setProperty("swiftmetrics.version", SWIFTMETRICS_VERSION)
    loaderApi.logMessage(info, "Swift Application Metrics")
  }

  deinit {
    self.stop()
  }

  private func testLatency() {
    if(latencyEnabled) {
      // Run every two seconds
     jobsQueue.async {
        sleep(2)
        let preDispatchTime = Date().timeIntervalSince1970 * 1000;
        DispatchQueue.global().async {
          let timeNow = Date().timeIntervalSince1970 * 1000
          let latencyTime = timeNow - preDispatchTime
          self.emitData(LatencyData(timeOfSample: Int(preDispatchTime), duration:latencyTime))
          self.testLatency()
        }
      }
    }
  }

private func executableFolderURL() -> URL {
#if os(Linux)
    let actualExecutableURL = Bundle.main.executableURL
                              ?? URL(fileURLWithPath: "/proc/self/exe").resolvingSymlinksInPath()
    return actualExecutableURL.appendingPathComponent("..").standardized
#else
    let actualExecutableURL = Bundle.main.executableURL
                              ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardized
    let actualExecutableFolderURL = actualExecutableURL.appendingPathComponent("..").standardized

    if (Bundle.main.executableURL?.lastPathComponent != "xctest") {
        return actualExecutableFolderURL
    } else {
        // We are running under the test runner, we may be able to work out the build directory that
        // contains the test program which is testing libraries in the project. That build directory
        // should also contain any executables associated with the project until this build type
        // (eg: release or debug)
        let loadedTestBundles = Bundle.allBundles.filter({ $0.isLoaded }).filter({ $0.bundlePath.hasSuffix(".xctest") })
        if loadedTestBundles.count > 0 {
            return loadedTestBundles[0].bundleURL.appendingPathComponent("..").standardized
        } else {
            return actualExecutableFolderURL
        }
    }
#endif
}

  private func getDefaultLibraryPath() -> String? {
    if isRunningOnCloud {
      // We're in Bluemix, don't set the search path, we don't want to
      // dynamically load plugins
      return nil
    } else {
      let programPath = CommandLine.arguments[0]

      if (programPath.contains("xctest")) { // running tests on Mac
        return executableFolderURL().path
      } else {
        if let lastSlashIndex = programPath.range(of: "/", options: .backwards) {
          return String(programPath[..<lastSlashIndex.lowerBound])
        } else {
          return "."
        }
      }
    }
  }

  private func loadProperties() throws {
    ///look for healthcenter.properties in current directory
    let fm = FileManager.default
    var propertiesPath = ""
    let localPropertiesPath = fm.currentDirectoryPath + "/swiftmetrics.properties"
    if fm.fileExists(atPath: localPropertiesPath) {
      propertiesPath = localPropertiesPath
    } else {
      ///use the one in the SwiftMetrics source
      propertiesPath = self.localSourceDirectory + "/swiftmetrics.properties"
    }
    _ = loaderApi.loadPropertiesFile(propertiesPath)
  }

  public func setPluginSearch(toDirectory: URL) {
    if toDirectory.isFileURL {
      loaderApi.logMessage(debug, "setPluginSearch(): Setting plugin path to \(toDirectory.path)")
      loaderApi.setProperty("com.ibm.diagnostics.healthcenter.plugin.path", toDirectory.path)
    } else {
      loaderApi.logMessage(warning, "setPluginSearch(): toDirectory is not a valid File URL")
    }
  }

  public func stop() {
    self.latencyEnabled = false
    if running {
      if swiftMon != nil {
        swiftMon!.stop()
      }
      loaderApi.logMessage(fine, "stop(): Shutting down Swift Application Metrics")
      running = false
      loaderApi.stop()
      loaderApi.shutdown()
      swiftMon = nil
    } else {
      loaderApi.logMessage(fine, "stop(): Swift Application Metrics has already stopped")
    }
  }

  private func macOSLibraryFileName(for name: String) -> String { return "lib\(name).dylib" }
  private func linuxLibraryFileName(for name: String) -> String { return "lib\(name).so" }
  private func platformLibraryFileName(for name: String) -> String {
    #if os(Linux)
    return linuxLibraryFileName(for: name)
    #else
    return macOSLibraryFileName(for: name)
    #endif
  }

  private func cloudLibraryPath(for name: String) -> String {
    return fileJoin(path: CLOUD_LIBRARY_PATH, fileName: linuxLibraryFileName(for: name))
  }

  private func xcodeLibraryPath(for name: String) -> String {
    return "@rpath/\(name).framework/Versions/A/\(name)"
  }

  private func pluginSearchLibraryPath(for name: String) -> String {
    return fileJoin(path: pluginSearchPath, fileName: platformLibraryFileName(for: name))
  }

  private var pluginSearchPath: String {
    guard let cPath = loaderApi.getProperty("com.ibm.diagnostics.healthcenter.plugin.path") else {
      return ""
    }
    return String(cString: cPath)
  }

  public func start() {
    if !running {
      loaderApi.logMessage(fine, "start(): Starting Swift Application Metrics")
      running = true
      if pluginSearchPath == "", let defaultLibraryPath = getDefaultLibraryPath() {
        self.setPluginSearch(toDirectory: URL(fileURLWithPath: defaultLibraryPath, isDirectory: true))
      }
      if !initialized {
        if isRunningOnCloud {
          // Attempt to load plugins already resident in the process
          loaderApi.addPlugin(cloudLibraryPath(for: "envplugin"))
          loaderApi.addPlugin(cloudLibraryPath(for: "memplugin"))
          loaderApi.addPlugin(cloudLibraryPath(for: "cpuplugin"))
          loaderApi.addPlugin(cloudLibraryPath(for: "hcapiplugin"))
        }
#if os(macOS)
        // Add plugins one by one in case built with xcode as plugin search path won't work
        loaderApi.addPlugin(xcodeLibraryPath(for: "envplugin"))
        loaderApi.addPlugin(xcodeLibraryPath(for: "memplugin"))
        loaderApi.addPlugin(xcodeLibraryPath(for: "cpuplugin"))
        loaderApi.addPlugin(xcodeLibraryPath(for: "hcapiplugin"))
#endif
        _ = loaderApi.initialize()
        initialized = true
      }

      if !initMonitorApi() {
        loaderApi.logMessage(warning, "Failed to initialize monitoring API")
      }
      loaderApi.start()
    } else {
      loaderApi.logMessage(
        fine, "start(): Swift Application Metrics has already started")
    }
    self.latencyEnabled = true
    testLatency()
  }

  public func enable(type: String, config: Any? = nil) {
    if config != nil {
      setConfig(type: type, config: config as Any)
    }
  }

  public func disable(type: String) {
    ///Can't disable common plugins
  }

  public func setConfig(type: String, config: Any) {
    ///this seems to be probe-related - might not be needed
  }

  public func emitData(_ data: LatencyData) {
    if let monitor = swiftMon {
      monitor.raiseEvent(data: data)
    }
  }

  public func emitData<T: SMData>(_ data: T) {
    if let monitor = swiftMon {
      monitor.raiseEvent(data: data)
    }
    ///add HC-visual events here
  }

  func localConnect() {
    if isMonitorApiValid() {
      loaderApi.logMessage(fine, "localConnect(): Registering receiveAgentCoreData")
      registerListener!(receiveAgentCoreData)
    } else {
      loaderApi.logMessage(warning, "Monitoring API is not initialized")
    }
  }

  private func fileJoin(path: String, fileName: String) -> String {
    loaderApi.logMessage(debug, "fileJoin(): Returning \(path)/\(fileName)")
    return path + "/" + fileName
  }

  private func openLibrary(at libraryPath: String) -> UnsafeMutableRawPointer? {
    guard let handle = dlopen(libraryPath, RTLD_LAZY) else {
      let error = String(cString: dlerror())
      loaderApi.logMessage(fine, "Failed to open library at path \(libraryPath): \(error)")
      return nil
    }
    return handle
  }

  private var monitorApiLibraryHandleCache: UnsafeMutableRawPointer? = nil
  private var monitorApiLibraryHandle: UnsafeMutableRawPointer? {
    if let fromCache = monitorApiLibraryHandleCache { return fromCache }
    // Load the library (failures logged in openLibrary())
    let handle: UnsafeMutableRawPointer?
    if isRunningOnCloud {
        handle = openLibrary(at: cloudLibraryPath(for: "hcapiplugin"))
    } else {
        handle = openLibrary(at: xcodeLibraryPath(for: "hcapiplugin")) ?? openLibrary(at: pluginSearchLibraryPath(for: "hcapiplugin"))
    }
    monitorApiLibraryHandleCache = handle
    return handle
  }

  private func getMonitorApiFunction(functionName: String) -> UnsafeMutableRawPointer? {
    loaderApi.logMessage(debug, "getMonitorApiFunction(): Looking for function \(functionName) in library libhcapiplugin")
    guard let handle = monitorApiLibraryHandle else {
      // Failure already logged in the computed property
      return nil
    }
    guard let function = dlsym(handle, functionName) else {
      let error = String(cString: dlerror())
      loaderApi.logMessage(warning, "Failed to find symbol \(functionName) in library libhcapiplugin: \(error)")
      return nil
    }
    loaderApi.logMessage(fine, "getMonitorApiFunction(): Function \(functionName) found")
    return function
  }

  private func isMonitorApiValid() -> Bool {
    loaderApi.logMessage(debug, "isMonitorApiValid(): Returning \(pushData != nil) && \(sendControl != nil) && \(registerListener != nil)")
    return (pushData != nil) && (sendControl != nil) && (registerListener != nil)
  }

  private func initMonitorApi() -> Bool {
    guard let iPushData = getMonitorApiFunction(functionName: "pushData") else {
      loaderApi.logMessage(debug, "initMonitorApi(): Unable to locate pushData. Returning.")
      return false
    }
    pushData = unsafeBitCast(iPushData, to: monitorPushData.self)

    guard let iSendControl = getMonitorApiFunction(functionName: "sendControl") else {
      loaderApi.logMessage(debug, "initMonitorApi(): Unable to locate sendControl. Returning.")
      return false
    }
    sendControl = unsafeBitCast(iSendControl, to: monitorSendControl.self)

    guard let iRegisterListener = getMonitorApiFunction(functionName: "registerListener") else {
      loaderApi.logMessage(debug, "initMonitorApi(): Unable to locate registerListener. Returning.")
      return false
    }
    registerListener = unsafeBitCast(iRegisterListener, to: monitorRegisterListener.self)

    return true
  }

  public func monitor() -> SwiftMonitor {
    if swiftMon == nil {
      swiftMon = SwiftMonitor(swiftMetrics: self)
    }
    return swiftMon!
  }
}
