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
   public typealias genericClosure<T: Data> = (T) -> ()
   public typealias envClosure = ([ String : String ]) -> ()

   final class EventEmitter {
      static var cpuObservers: [cpuClosure] = []
      static var memoryObservers: [memoryClosure] = []
      static var environmentObservers: [envClosure] = []
      static var initializedObservers: [envClosure] = []
      static var anyObservers : [ String : [(Any) -> ()] ] = [:]
      static var genericObservers: [String : [genericClosure<GenericData>]] = [:]

      static func publish(cpuData: CPUData) {
         for process in cpuObservers {
            process(cpuData)
         }
      }

      static func publish(memData: MemData) {
         for process in memoryObservers {
            process(memData)
         }
      }

      static func publish(envData: [ String: String ]) {
         for process in environmentObservers {
            process(envData)
         }
      }

      static func publish(type: String, envData: [ String: String ]) {
         //currently this is only executed by the initialized event
         for process in initializedObservers {
            process(envData)
         }
      }

      static func publish(topic: String, data: GenericData) {
         if genericObservers[topic] != nil {
            for process in genericObservers[topic]! {
              process(data)
            }
         }
      }

      static func publish(topic: String, data: Any) {
         if anyObservers[topic] != nil {
            for process in anyObservers[topic]! {
              process(data)
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

      static func subscribe(topic: String, callback: @escaping envClosure) {
         ///currently this is only executed by initialized observers
         initializedObservers.append(callback)
      }

      static func subscribe(topic: String, callback: @escaping genericClosure<GenericData>) {
         if genericObservers[topic] != nil {
            genericObservers[topic]!.append(callback)
         } else {
            genericObservers[topic] = [callback]
         }
      }

      static func subscribe(topic: String, callback: @escaping ((Any) -> ())) {
         if anyObservers[topic] != nil {
            anyObservers[topic]!.append(callback)
         } else {
            anyObservers[topic] = [callback]
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
            raiseEvent(type: "cpu", data: cpu)
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
            raiseEvent(type: "memory", data: memory)
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
      raiseEvent(type: "environment", data: env)
      if self.initialized > 0 {
         self.initialized -= 1
         if self.initialized == 0 {
            raiseEvent(type: "initialized", data: self.getEnvironmentData())
         }
      }
   }

   private func setEnv(_ env: [ String : String ]) {
      for (key, value) in env {
         self.environment[key] = value
      }
   }

   public func on<T: Data>(dataType: String, _ callback: @escaping (T) -> ()) {
      swiftMet.loaderApi.logMessage(fine, "on(): Subscriving a \(type(of: callback)) closure to an \(dataType) event")
   }
   
   public func on(dataType: String, _ callback: @escaping cpuClosure) {
      on(callback)
   }

   public func on(_ callback: @escaping cpuClosure) {
      swiftMet.loaderApi.logMessage(debug, "on(): Subscribing a CPU observer")
      EventEmitter.subscribe(callback: callback)
   }

   public func on(dataType: String, _ callback: @escaping memoryClosure) {
      on(callback)
   }

   public func on(_ callback: @escaping memoryClosure) {
      swiftMet.loaderApi.logMessage(debug, "on(): Subscribing a Memory observer")
      EventEmitter.subscribe(callback: callback)
   }

   public func on (dataType: String, _ callback: @escaping envClosure) {
      ///test for envClosure types, otherwise generify
      switch dataType {
         case "environment":
            swiftMet.loaderApi.logMessage(debug, "on(): Subscribing an Environment observer")
            EventEmitter.subscribe(callback: callback)
         case "initialized":
            swiftMet.loaderApi.logMessage(debug, "on(): Subscribing an Initialized observer")
            EventEmitter.subscribe(topic: dataType, callback: callback)
         default:
            swiftMet.loaderApi.logMessage(debug, "on(): Subscribing an observer")
      }
   }
   
   public func on(dataType: String, _ callback: @escaping ((Any) -> ())) {
      swiftMet.loaderApi.logMessage(debug, "on(): Subscribing a \(dataType) observer")
      EventEmitter.subscribe(topic: dataType, callback: callback)
   }

   func raiseEvent<T: Data>(type: String, data: T) {
      swiftMet.loaderApi.logMessage(fine, "raiseEvent(): Raising a \(type) event containing a \(type(of: data)) object")
      switch data {
         case let cpu as CPUData:
            swiftMet.loaderApi.logMessage(debug, "raiseEvent(): Publishing a CPU event")
            EventEmitter.publish(cpuData: cpu)
         case let mem as MemData:
            swiftMet.loaderApi.logMessage(debug, "raiseEvent(): Publishing a Memory event")
            EventEmitter.publish(memData: mem)
         default:
            swiftMet.loaderApi.logMessage(debug, "raiseEvent(): Publishing a Default event")
            EventEmitter.publish(topic: type, data: data as! GenericData)
      }
   }

   private func raiseEvent(type: String, data: [ String : String ]) {
      if type == "environment" {
         swiftMet.loaderApi.logMessage(debug, "raiseEvent(): Publishing an Environment event")
         EventEmitter.publish(envData: data)
      } else if type == "initialized" {
         swiftMet.loaderApi.logMessage(debug, "raiseEvent(): Publishing an Initialized event")
         EventEmitter.publish(type: type, envData: data)
      }
   }

   func raiseLocalEvent(type: String, data: Any) {
      swiftMet.loaderApi.logMessage(debug, "raiseEvent(): Publishing a \(type) event")
      EventEmitter.publish(topic : type, data: data)
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
            ///raise unknown messages as GenericEvent so it can be parsed further down the line
            raiseEvent(type: topic, data: GenericData(timeOfSample: 0, message:message))
      }
   }

}
