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
import Foundation
import agentcore

public class SwiftMonitor {

  let swiftMetrics: SwiftMetrics
  var environment: [ String : String ] = [:]
  var initialized: Int = 1

  init(swiftMetrics: SwiftMetrics) {
    swiftMetrics.loaderApi.logMessage(fine, "Creating SwiftMonitor with local connection.")
    self.swiftMetrics = swiftMetrics
    swiftMetrics.start()
    swiftMetrics.localConnect()
  }

  public func getEnvironmentData() -> [ String : String ] {
    return self.environment
  }

  public typealias cpuClosure = (CPUData) -> ()
  public typealias memoryClosure = (MemData) -> ()
  public typealias envClosure = (EnvData) -> ()
  public typealias initClosure = (InitData) -> ()
  public typealias latencyClosure = (LatencyData) -> ()

  private var running = true

  final public class EventEmitter {
    static var cpuObservers: [cpuClosure] = []
    static var memoryObservers: [memoryClosure] = []
    static var environmentObservers: [envClosure] = []
    static var initializedObservers: [initClosure] = []
    static var latencyObservers: [latencyClosure] = []
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

    static func publish(data: LatencyData) {
        for process in latencyObservers {
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

    static func subscribe(callback: @escaping latencyClosure) {
      latencyObservers.append(callback)
    }

    static func subscribe<T: SMData>(callback: @escaping (T) -> ()) {
      let index = "\(T.self)"
      if var observer = customObservers[index] {
        observer.append(callback as Any)
        customObservers[index] = observer
      } else {
        customObservers[index] = [callback as Any]
      }
    }

  }

  private func formatCPU(messages: String) {
    if(running) {
      for message in messages.components(separatedBy: "\n") {
        if message.contains("@#") {
          swiftMetrics.loaderApi.logMessage(debug, "formatCPU(): Raising CPU event")
          //cpu: startCPU@#1412609879696@#0.00499877@#0.137468
          let values = message.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).components(separatedBy: "@#")
          if let timeOfSample = Int(values[1]), let percentUsedByApplication = Float(values[2]),
          let percentUsedBySystem = Float(values[3]) {
            let cpu = CPUData(timeOfSample: timeOfSample, percentUsedByApplication: percentUsedByApplication,
              percentUsedBySystem: percentUsedBySystem)
              raiseEvent(data: cpu)
          } else {
            swiftMetrics.loaderApi.logMessage(warning, "formatCPU(): Could not obtain/parse CPU usage data.")
          }
        }
      }
    }
  }

  private func formatMemory(messages: String) {
    if(running) {
      for message in messages.components(separatedBy: "\n") {
        if message.contains(",") {
          swiftMetrics.loaderApi.logMessage(debug, "formatMemory(): Raising Memory event")
          ///MemorySource,1415976582652,totalphysicalmemory=16725618688,physicalmemory=52428800,privatememory=374747136,virtualmemory=374747136,freephysicalmemory=1591525376
          let values = message.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).components(separatedBy: ",")
          if let physicalTotal = Int(values[2].components(separatedBy: "=")[1]),
          let physicalFree = Int(values[6].components(separatedBy: "=")[1]),
          let timeOfSample = Int(values[1]),
          let applicationAddressSpaceSize = Int(values[5].components(separatedBy: "=")[1]),
          let applicationPrivateSize = Int(values[4].components(separatedBy: "=")[1]),
          let applicationRAMUsed = Int(values[3].components(separatedBy: "=")[1]) {
            let physicalUsed = (physicalTotal >= 0 && physicalFree >= 0) ? (physicalTotal - physicalFree) : -1
            let memory = MemData(timeOfSample: timeOfSample,
              totalRAMOnSystem: physicalTotal,
              totalRAMUsed: physicalUsed,
              totalRAMFree: physicalFree,
              applicationAddressSpaceSize: applicationAddressSpaceSize,
              applicationPrivateSize: applicationPrivateSize,
              applicationRAMUsed: applicationRAMUsed)
              raiseEvent(data: memory)
          }
        }
      }
    }
  }

  private func formatOSEnv(message: String) {
    if(running) {
      swiftMetrics.loaderApi.logMessage(debug, "formatOSEnv(): Raising OS Environment event")
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
        if value.contains("="), let firstEquals = value.index(of: "=") {
          env[String(value[..<firstEquals])] = String(value[value.index(after: firstEquals)...])
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
  }

  private func setEnv(_ env: [ String : String ]) {
    for (key, value) in env {
      self.environment[key] = value
    }
  }

  public func on(_ callback: @escaping cpuClosure) {
    swiftMetrics.loaderApi.logMessage(fine, "on(): Subscribing a CPUData observer")
    EventEmitter.subscribe(callback: callback)
  }

  public func on(_ callback: @escaping memoryClosure) {
    swiftMetrics.loaderApi.logMessage(fine, "on(): Subscribing a MemData observer")
    EventEmitter.subscribe(callback: callback)
  }

  public func on(_ callback: @escaping envClosure) {
    swiftMetrics.loaderApi.logMessage(fine, "on(): Subscribing an EnvData observer")
    EventEmitter.subscribe(callback: callback)
  }

  public func on(_ callback: @escaping initClosure) {
    swiftMetrics.loaderApi.logMessage(fine, "on(): Subscribing an InitData observer")
    EventEmitter.subscribe(callback: callback)
  }

  public func on(_ callback: @escaping latencyClosure) {
    swiftMetrics.loaderApi.logMessage(fine, "on(): Subscribing a LatencyData observer")
    EventEmitter.subscribe(callback: callback)
  }

  public func on<T: SMData>(_ callback: @escaping (T) -> ()) {
    swiftMetrics.loaderApi.logMessage(fine, "on(): Subscribing a \(T.self)) observer")
    EventEmitter.subscribe(callback: callback)
  }

  public func stop() {
    running = false
  }

  func raiseEvent(data: CPUData) {
    if(running) {
      swiftMetrics.loaderApi.logMessage(fine, "raiseEvent(): Publishing a CPUData event")
      EventEmitter.publish(data: data)
    }
  }

  func raiseEvent(data: MemData) {
    if(running) {
      swiftMetrics.loaderApi.logMessage(fine, "raiseEvent(): Publishing a MemData event")
      EventEmitter.publish(data: data)
    }
  }

  func raiseEvent(data: EnvData) {
    if(running) {
      swiftMetrics.loaderApi.logMessage(fine, "raiseEvent(): Publishing an EnvData event")
      EventEmitter.publish(data: data)
    }
  }

  func raiseEvent(data: InitData) {
    if(running) {
      swiftMetrics.loaderApi.logMessage(fine, "raiseEvent(): Publishing an InitData event")
      EventEmitter.publish(data: data)
    }
  }

  func raiseEvent(data: LatencyData) {
    if(running) {
      swiftMetrics.loaderApi.logMessage(fine, "raiseEvent(): Publishing a LatencyData event")
      EventEmitter.publish(data: data)
    }
  }

  func raiseEvent<T: SMData>(data: T) {
    if(running) {
      swiftMetrics.loaderApi.logMessage(fine, "raiseEvent(): Publishing a \(T.self) event")
      EventEmitter.publish(data: data)
    }
  }

  func raiseCoreEvent(topic: String, message: String) {
    if(running) {
      swiftMetrics.loaderApi.logMessage(debug, "raiseCoreEvent(): Raising core event: topic = \(topic)")
      switch topic {
        case "common_cpu", "cpu":
          formatCPU(messages: message)
        case "common_memory", "memory":
          formatMemory(messages: message)
        case "common_env":
          formatOSEnv(message: message)
        default:
          ///ignore other messages
          swiftMetrics.loaderApi.logMessage(debug, "raiseCoreEvent(): Topic not recognised - ignoring event")
       }
    }
  }

}
