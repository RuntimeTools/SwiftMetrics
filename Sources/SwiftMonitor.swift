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

   public func getEnvironment() -> [ String : String ] {
      return self.environment
   }


   final class EventEmitter {
      static var observers: [ String : [Any] ] = [:]

      static func publish<T: Event>(event: T) {
         let index = "\(T.self)"
         if observers[index] != nil {
            for process in observers[index]! {
               (process as! ((T) -> ()))(event)
            }
         }
      }

      static func subscribe<T: Event>(callback: @escaping (T) -> ()) {
         let index = "\(T.self)"
         if observers[index] != nil {
            observers[index]!.append(callback as Any)
         } else {
            observers[index] = [callback as Any]
         }
      }

   }

   private func formatCPU(messages: String) {
      for message in messages.components(separatedBy: "\n") {
         if message.contains("@#") {
            swiftMet.loaderApi.logMessage(debug, "formatCPU(): Raising CPU event")
            //cpu: startCPU@#1412609879696@#0.00499877@#0.137468
            let values = message.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).components(separatedBy: "@#")
            let cpu = CPUEvent(time: Int(values[1])!, process: Float(values[2])!, system: Float(values[3])!)
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
            let memory = MemEvent(time: Int(values[1])!,
                                  physical_total: physicalTotal,
                                  physical_used: physicalUsed,
                                  physical_free: physicalFree,
                                  virtual: Int(values[5].components(separatedBy: "=")[1])!,
                                  private: Int(values[4].components(separatedBy: "=")[1])!,
                                  physical: Int(values[3].components(separatedBy: "=")[1])!)
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
      let environment = EnvEvent(data: self.getEnvironment())
      raiseEvent(data: environment)
      if self.initialized > 0 {
         self.initialized -= 1
         if self.initialized == 0 {
            let initE = InitEvent(data: self.getEnvironment())
            raiseEvent(data: initE)
         }
      }
   }

   private func setEnv(_ env: [ String : String ]) {
      for (key, value) in env {
         self.environment[key] = value
      }
   }

   public func on<T: Event>(_ callback: @escaping (T) -> ()) {
      swiftMet.loaderApi.logMessage(fine, "on(): Subscribing a \(type(of: callback)) observer")
      EventEmitter.subscribe(callback: callback)
   }
   

   func raiseEvent<T: Event>(data: T) {
      swiftMet.loaderApi.logMessage(fine, "raiseEvent(): Publishing a \(T.self) event")
      EventEmitter.publish(event: data)
   }
   
   func raiseCoreEvent(topic: String, message: String) {
      swiftMet.loaderApi.logMessage(debug, "raiseCoreEvent(): Formatting core event: topic = \(topic)")
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
