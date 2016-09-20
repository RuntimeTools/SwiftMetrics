import agentcore
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

public protocol Event {
   var time: Int { get }
}

public struct CPUEvent: Event {
   public let time: Int 
   public let process: Float 
   public let system: Float
}   

public struct MemEvent: Event {
   public let time: Int
   public let physical_total: Int
   public let physical_used: Int
   public let physical_free: Int
   public let virtual: Int
   public let `private`: Int
   public let physical: Int
}

public struct GenericEvent: Event {
   public var time: Int
   public var message: String
}

private var swiftMon: SwiftMonitor?


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

public class SwiftMetrics {

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
        self.setDefaultLibraryPath()
        self.start()
    }

    deinit {
        self.stop()
    }

    private func setDefaultLibraryPath() {
       ///use the directory that the swift program lives in
       let programPath = CommandLine.arguments[0]
       let i = programPath.range(of: "/", options: .backwards)
       let defaultLibraryPath = programPath.substring(to: i!.lowerBound)
       loaderApi.logMessage(fine, "setDefaultLibraryPath(): to \(defaultLibraryPath)")
       self.spath(path: defaultLibraryPath)
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
          var packagesPath = workingPath.substring(to: i!.lowerBound)
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

    public func spath(path: String) {
        loaderApi.logMessage(debug, "spath(): Setting plugin path to \(path)")
        loaderApi.setProperty("com.ibm.diagnostics.healthcenter.plugin.path", path)
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
            _ = loaderApi.initialize()
            loaderApi.logMessage(debug, "start(): Forcing MQTT Connection on")
            loaderApi.setProperty("com.ibm.diagnostics.healthcenter.mqtt", "on")
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
          setConfig(type: type, config: config)
       }
    }

    public func disable(type: String) {
       ///Can't disable common plugins
    }

    public func setConfig(type: String, config: Any) {
      ///this seems to be probe-related - might not be needed
    }

    public func emit(type: String, data: Any) {
      if swiftMon != nil {
         swiftMon!.raiseLocalEvent(type: type, data: data)
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
          swiftMon = SwiftMonitor(swiftMet: self)
       }
       return swiftMon!
    }
}
