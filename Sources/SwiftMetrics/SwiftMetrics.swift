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
import CloudFoundryConfig
#if os(Linux)
import Glibc
#else
import Darwin
#endif

public protocol SMData {
}

public struct CPUData: SMData {
  public let timeOfSample: Int
  public let percentUsedByApplication: Float
  public let percentUsedBySystem: Float
}

public struct MemData: SMData {
  public let timeOfSample: Int
  public let totalRAMOnSystem: Int
  public let totalRAMUsed: Int
  public let totalRAMFree: Int
  public let applicationAddressSpaceSize: Int
  public let applicationPrivateSize: Int
  public let applicationRAMUsed: Int
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
    let message = String(bytesNoCopy: data, length: size, encoding: String.Encoding.utf8, freeWhenDone: false) ?? ""
    if swiftMon != nil {
      swiftMon!.raiseCoreEvent(topic: source, message: message)
    }
  }
}

open class SwiftMetrics {

  let loaderApi: loaderCoreFunctions
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
  public let localSourceDirectory: String

  public init() throws {
    self.loaderApi = loader_entrypoint().pointee
    //find the SwiftMetrics directory where swiftmetrics.properties and SwiftMetricsDash public folder are
    let fm = FileManager.default
    let currentDir = fm.currentDirectoryPath
    let configMgr = ConfigurationManager().load(.environmentVariables)
    var applicationPath = ""
    if (configMgr.isLocal) {
      var workingPath = ""
      if currentDir.contains(".build") {
        ///we're below the Packages directory
        workingPath = currentDir
      } else {
        ///we're above the Packages directory
        workingPath = CommandLine.arguments[0]
      }
      if let i = workingPath.range(of: ".build") {
        applicationPath = workingPath.substring(to: i.lowerBound)
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


  private func setDefaultLibraryPath() {
    var defaultLibraryPath = "."
    let configMgr = ConfigurationManager().load(.environmentVariables)
    loaderApi.logMessage(fine, "setDefaultLibraryPath(): isLocal: \(configMgr.isLocal)")
    if (configMgr.isLocal) {
      let programPath = CommandLine.arguments[0]

      /// Absolute path to the executable's folder
      let executableFolder = executableFolderURL().path

      if(programPath.contains("xctest")) { // running tests on Mac
        defaultLibraryPath = executableFolder
      } else {
        let i = programPath.range(of: "/", options: .backwards)
        if i != nil {
          defaultLibraryPath = programPath.substring(to: i!.lowerBound)
        }
      }
    } else {
      // We're in Bluemix, use the path the swift-buildpack saves libraries to
      defaultLibraryPath = "/home/vcap/app/.swift-lib"
    }
    loaderApi.logMessage(fine, "setDefaultLibraryPath(): to \(defaultLibraryPath)")
    self.setPluginSearch(toDirectory: URL(fileURLWithPath: defaultLibraryPath, isDirectory: true))
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
    if (running) {
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

  public func start() {
    if (!running) {
      loaderApi.logMessage(fine, "start(): Starting Swift Application Metrics")
      running = true
      let pluginSearchPath = String(cString: loaderApi.getProperty("com.ibm.diagnostics.healthcenter.plugin.path")!)
      if pluginSearchPath == "" {
        self.setDefaultLibraryPath()
      }
      if(!initialized) {
        // Add plugins one by one in case built with xcode as plugin search path won't work
        loaderApi.addPlugin("@rpath/envplugin.framework/Versions/A/envplugin")
        loaderApi.addPlugin("@rpath/memplugin.framework/Versions/A/memplugin")
        loaderApi.addPlugin("@rpath/cpuplugin.framework/Versions/A/cpuplugin")
        loaderApi.addPlugin("@rpath/hcapiplugin.framework/Versions/A/hcapiplugin")
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

  private func getFunctionFromLibrary(libraryPath: String, functionName: String) -> UnsafeMutableRawPointer? {
    loaderApi.logMessage(debug, "getFunctionFromLibrary(): Looking for function \(functionName) in library \(libraryPath)")
    var handle = dlopen(libraryPath, RTLD_LAZY)
    if(handle == nil) {
        let error = String(cString: dlerror())
        loaderApi.logMessage(warning, "Failed to open library \(libraryPath): \(error)")
        // try xcode location
        handle = dlopen("@rpath/hcapiplugin.framework/Versions/A/hcapiplugin", RTLD_LAZY)
        if(handle == nil) {
            let error = String(cString: dlerror())
            loaderApi.logMessage(warning, "Failed to open library \("@rpath/agentcore.framework/Versions/A/agentcore"): \(error)")
            return nil
        }
    }
    guard let function = dlsym(handle, functionName) else {
      let error = String(cString: dlerror())
      loaderApi.logMessage(warning, "Failed to find symbol \(functionName) in library \(libraryPath): \(error)")
      dlclose(handle!)
      return nil
    }
    dlclose(handle!)
    loaderApi.logMessage(fine, "getFunctionFromLibrary(): Function \(functionName) found")
    return function
  }

  private func getMonitorApiFunction(pluginPath: String, functionName: String) -> UnsafeMutableRawPointer? {
    #if os(Linux)
    let libname = "libhcapiplugin.so"
    #else
    let libname = "libhcapiplugin.dylib"
    #endif
    return getFunctionFromLibrary(libraryPath: fileJoin(path: pluginPath, fileName: libname), functionName: functionName)
  }

  private func isMonitorApiValid() -> Bool {
    loaderApi.logMessage(debug, "isMonitorApiValid(): Returning \(pushData != nil) && \(sendControl != nil) && \(registerListener != nil)")
    return (pushData != nil) && (sendControl != nil) && (registerListener != nil)
  }

  private func initMonitorApi() -> Bool {
    let pluginPath = String(cString: loaderApi.getProperty("com.ibm.diagnostics.healthcenter.plugin.path")!)

    guard let iPushData = getMonitorApiFunction(pluginPath: pluginPath, functionName: "pushData") else {
      loaderApi.logMessage(debug, "initMonitorApi(): Unable to locate pushData. Returning.")
      return false
    }
    pushData = unsafeBitCast(iPushData, to: monitorPushData.self)

    guard let iSendControl = getMonitorApiFunction(pluginPath: pluginPath, functionName: "sendControl") else {
      loaderApi.logMessage(debug, "initMonitorApi(): Unable to locate sendControl. Returning.")
      return false
    }
    sendControl = unsafeBitCast(iSendControl, to: monitorSendControl.self)

    guard let iRegisterListener = getMonitorApiFunction(pluginPath: pluginPath, functionName: "registerListener") else {
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

