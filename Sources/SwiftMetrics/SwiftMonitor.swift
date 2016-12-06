import Foundation
import agentcore

public class SwiftMonitor {

   let swiftMet: SwiftMetrics
   var environment: [ String : String ] = [:]
   var initialized: Int = 1

   init(swiftMet: SwiftMetrics) {
      swiftMet.loaderApi.logMessage(fine, "Creating SwiftMonitor with local connection")
      self.swiftMet = swiftMet
      swiftMet.start()
      swiftMet.localConnect()
   }

   public func getEnvironmentData() -> [ String : String ] {
      return self.environment
   }

   public typealias cpuClosure = (CPUData) -> ()
   public typealias memoryClosure = (MemData) -> ()
   public typealias envClosure = (EnvData) -> ()
   public typealias initClosure = (InitData) -> ()

   final public class EventEmitter {
      static var cpuObservers: [cpuClosure] = []
      static var memoryObservers: [memoryClosure] = []
      static var environmentObservers: [envClosure] = []
      static var initializedObservers: [initClosure] = []
      static var customObservers : [ String : [Any] ] = [:]

      static func publish(data: CPUData) {
         for process in cpuObservers {
            process(data)
         }
      }

      static func publish(data: MemData) {
         for process in memoryObservers {
            process(data)
         }
      }

      static func publish(data: EnvData) {
         for process in environmentObservers {
            process(data)
         }
      }

      static func publish(data: InitData) {
         for process in initializedObservers {
            process(data)
         }
      }

      static func publish<T: SMData>(data: T) {
         let index = "\(T.self)"
         if let closureList = customObservers[index] {
            for closure in closureList {
              (closure as! (T) -> ())(data)
            }
         }
      }

      static func subscribe(callback: @escaping cpuClosure) {
         cpuObservers.append(callback)
      }

      static func subscribe(callback: @escaping memoryClosure) {
         memoryObservers.append(callback)
      }

      static func subscribe(callback: @escaping envClosure) {
         environmentObservers.append(callback)
      }

      static func subscribe(callback: @escaping initClosure) {
         initializedObservers.append(callback)
      }

      static func subscribe<T: SMData>(callback: @escaping (T) -> ()) {
         let index = "\(T.self)"
         if customObservers[index] != nil {
            customObservers[index]!.append(callback as Any) 
         } else {
            customObservers[index] = [callback as Any]
         }
      }

   }

   private func formatCPU(messages: String) {
      for message in messages.components(separatedBy: "\n") {
         if message.contains("@#") {
            swiftMet.loaderApi.logMessage(debug, "formatCPU(): Raising CPU event")
            //cpu: startCPU@#1412609879696@#0.00499877@#0.137468
            let values = message.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).components(separatedBy: "@#")
            let cpu = CPUData(timeOfSample: Int(values[1])!, percentUsedByApplication: Float(values[2])!,
                              percentUsedBySystem: Float(values[3])!)
            raiseEvent(data: cpu)
         }
      }
   }

   private func formatMemory(messages: String) {
      for message in messages.components(separatedBy: "\n") {
         if message.contains(",") {
            swiftMet.loaderApi.logMessage(debug, "formatMemory(): Raising Memory event")
            ///MemorySource,1415976582652,totalphysicalmemory=16725618688,physicalmemory=52428800,privatememory=374747136,virtualmemory=374747136,freephysicalmemory=1591525376
            let values = message.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).components(separatedBy: ",")
            let physicalTotal = Int(values[2].components(separatedBy: "=")[1])!
            let physicalFree = Int(values[6].components(separatedBy: "=")[1])!
            let physicalUsed = (physicalTotal >= 0 && physicalFree >= 0) ? (physicalTotal - physicalFree) : -1
            let memory = MemData(timeOfSample: Int(values[1])!,
                                 totalRAMOnSystem: physicalTotal,
                                 totalRAMUsed: physicalUsed,
                                 totalRAMFree: physicalFree,
                                 applicationAddressSpaceSize: Int(values[5].components(separatedBy: "=")[1])!,
                                 applicationPrivateSize: Int(values[4].components(separatedBy: "=")[1])!,
                                 applicationRAMUsed: Int(values[3].components(separatedBy: "=")[1])!)
            raiseEvent(data: memory)
         }
      }
   }

   private func formatOSEnv(message: String) {
      swiftMet.loaderApi.logMessage(debug, "formatOSEnv(): Raising OS Environment event")
      /* environment_os: #EnvironmentSource
         environment.LESSOPEN=| /usr/bin/lesspipe %s
         environment.GNOME_KEYRING_PID=1111
         environment.USER=exampleuser
         os.arch=X86_64
         os.name=Linux
         os.version=3.5.0-54-generic#81~precise1~Ubuntu SMP Tue Jul 15 04:02:22 UTC 2014
         pid=4838
         native.library.date=Oct 20 2014 10:51:56
         number.of.processors=2
         command.line=/home/exampleuser/SwiftMetrics/sample/.build/debug/test
      */
      let values = message.components(separatedBy: "\n")
      var env: [ String : String ] = [:]
      for value in values {
         if value.contains("=") {
            let firstEquals = value.characters.index(of: "=")!
            env[value.substring(to: firstEquals)] = value.substring(from: value.index(after: firstEquals))
         }
      }
      setEnv(env)
      let environment = EnvData(data: env)
      raiseEvent(data: environment)
      if self.initialized > 0 {
         self.initialized -= 1
         if self.initialized == 0 {
            let initE = InitData(data: self.getEnvironmentData())
            raiseEvent(data: initE)
         }
      }
   }

   private func setEnv(_ env: [ String : String ]) {
      for (key, value) in env {
         self.environment[key] = value
      }
   }

   public func on<T: SMData>(_ callback: @escaping (T) -> ()) {
      swiftMet.loaderApi.logMessage(fine, "on(): Subscribing a \(type(of: callback)) observer")
      EventEmitter.subscribe(callback: callback)
   }
   
   func raiseEvent<T: SMData>(data: T) {
      swiftMet.loaderApi.logMessage(fine, "raiseEvent(): Publishing a \(T.self) event")
      EventEmitter.publish(data: data)
   }

   func raiseCoreEvent(topic: String, message: String) {
      swiftMet.loaderApi.logMessage(debug, "raiseCoreEvent(): Raising core event: topic = \(topic)")
      switch topic {
         case "common_cpu", "cpu":
            formatCPU(messages: message)
         case "common_memory", "memory":
            formatMemory(messages: message)
         case "common_env":
            formatOSEnv(message: message)
         default:
            ///ignore other messages
            swiftMet.loaderApi.logMessage(debug, "raiseCoreEvent(): Topic not recognised - ignoring event")
      }
   }

}
