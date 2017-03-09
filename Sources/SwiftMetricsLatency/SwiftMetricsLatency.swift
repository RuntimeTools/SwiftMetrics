import SwiftMetrics
import Foundation
import Dispatch

public struct LatencyData: SMData {
  public let timeOfSample: Int
  public let duration: Double
}


public typealias latencyClosure = (LatencyData) -> ()

public extension SwiftMonitor.EventEmitter {

    static var latencyObservers: [latencyClosure] = []

    static func publish(data: LatencyData) {
        for process in latencyObservers {
            process(data)
        }
    }

    static func subscribe(callback: @escaping latencyClosure) {
        latencyObservers.append(callback)
    }

}

public extension SwiftMonitor {

  public func on(_ callback: @escaping latencyClosure) {
    EventEmitter.subscribe(callback: callback)
  }

  func raiseEvent(data: LatencyData) {
    EventEmitter.publish(data: data)
  }

}

public extension SwiftMetrics {

  public func emitData(_ data: LatencyData) {
    if let monitor = swiftMon {
      monitor.raiseEvent(data: data)
    }
  }

}

public class SwiftMetricsLatency {

    private let sm: SwiftMetrics
    private var enabled: Bool = true
    private let sleepInterval: UInt32 = 2

    public init(swiftMetricsInstance: SwiftMetrics){
        sm = swiftMetricsInstance
        DispatchQueue.global(qos: .background).async {
            self.snoozeLatencyEmit(Date().timeIntervalSince1970 * 1000)
        }
    }

    public func enable() {
        enabled = true
        DispatchQueue.global(qos: .background).async {
            self.snoozeLatencyEmit(Date().timeIntervalSince1970 * 1000)
        }
    }

    public func disable() {
        enabled = false
    }

    private func snoozeLatencyEmit(_ startTime: Double) {
        if (enabled) {
            let timeNow = Date().timeIntervalSince1970 * 1000
            let latencyTime = timeNow - startTime
            sm.emitData(LatencyData(timeOfSample: Int(startTime), duration:latencyTime))
            sleep(sleepInterval)
            DispatchQueue.global(qos: .background).async {
                self.snoozeLatencyEmit(Date().timeIntervalSince1970 * 1000)
            }
        }
    }
}
