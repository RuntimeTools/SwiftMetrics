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

public var swiftMon: SwiftMonitor?


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

  public init() throws{

    self.loaderApi = loader_entrypoint().pointee
    try self.loadProperties()
    loaderApi.setLogLevels()
    loaderApi.setProperty("agentcore.version", loaderApi.getAgentVersion())
    loaderApi.setProperty("swiftmetrics.version", SWIFTMETRICS_VERSION)
    loaderApi.logMessage(info, "Swift Application Metrics")
  }

  deinit {
    self.stop()
  }

  private func setDefaultLibraryPath() {
    var defaultLibraryPath = "."
    let configMgr = ConfigurationManager().load(.environmentVariables)
    loaderApi.logMessage(debug, "setDefaultLibraryPath(): isLocal: \(configMgr.isLocal)")
    if (configMgr.isLocal) {
      //if local, use the directory that the swift program lives in
      let programPath = CommandLine.arguments[0]
      let i = programPath.range(of: "/", options: .backwards)
      if i != nil {
        defaultLibraryPath = programPath.substring(to: i!.lowerBound)
      }
    } else {
      //if we're in Bluemix, use the path the swift-buildpack saves libraries to
      defaultLibraryPath = "/home/vcap/app/.swift-lib"
    }
    loaderApi.logMessage(fine, "setDefaultLibraryPath(): to \(defaultLibraryPath)")
    self.setPluginSearch(toDirectory: URL(fileURLWithPath: defaultLibraryPath, isDirectory: true))
  }

  private func loadProperties() throws {
    ///look for healthcenter.properties in current directory
    let fm = FileManager.default
    var propertiesPath = ""
    let currentDir = fm.currentDirectoryPath
    var dirContents = try fm.contentsOfDirectory(atPath: currentDir)
    for dir in dirContents {
      if dir.contains("healthcenter.properties") {
        propertiesPath = "\(currentDir)/\(dir)"
      }
    }
    if propertiesPath.isEmpty {
      ///need to go and look for it in the program's Packages directory
      var workingPath = ""
      if currentDir.contains(".build") {
        ///we're below the Packages directory
        workingPath = currentDir
      } else {
        ///we're above the Packages directory
        workingPath = CommandLine.arguments[0]
      }

      let i = workingPath.range(of: ".build")
      var packagesPath = ""
      if i == nil {
        // we could be in bluemix
        packagesPath="/home/vcap/app"
      } else {
        packagesPath = workingPath.substring(to: i!.lowerBound)
      }
      packagesPath.append("Packages")
      _ = fm.changeCurrentDirectoryPath(packagesPath)
      ///omr-agentcore has a version number in it, so search for it
      dirContents = try fm.contentsOfDirectory(atPath: fm.currentDirectoryPath)
      for dir in dirContents {
        if dir.contains("omr-agentcore") {
          ///that's where we want to be!
          _ = fm.changeCurrentDirectoryPath(dir)
        }
      }
      propertiesPath = "\(fm.currentDirectoryPath)/properties/healthcenter.properties"
      _ = fm.changeCurrentDirectoryPath(currentDir)

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
    if (running) {
      loaderApi.logMessage(fine, "stop(): Shutting down Swift Application Metrics")
      running = false
      loaderApi.stop()
      loaderApi.shutdown()
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
      _ = loaderApi.initialize()
      loaderApi.start()
    } else {
      loaderApi.logMessage(fine, "start(): Swift Application Metrics has already started")
    }
    if !initMonitorApi() {
      loaderApi.logMessage(warning, "Failed to initialize monitoring API")
    }
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

  public func emitData<T: SMData>(_ data: T) {
    if swiftMon != nil {
      swiftMon!.raiseEvent(data: data)
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
    guard let handle = dlopen(libraryPath, RTLD_LAZY) else {
      let error = String(cString: dlerror())
      loaderApi.logMessage(warning, "Failed to open library \(libraryPath): \(error)")
      return nil
    }
    guard let function = dlsym(handle, functionName) else {
      let error = String(cString: dlerror())
      loaderApi.logMessage(warning, "Failed to find symbol \(functionName) in library \(libraryPath): \(error)")
      dlclose(handle)
      return nil
    }
    dlclose(handle)
    loaderApi.logMessage(debug, "getFunctionFromLibrary(): Function found")
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
