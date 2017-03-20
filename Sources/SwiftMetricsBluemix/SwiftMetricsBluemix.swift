/**
* Copyright IBM Corporation 2017
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
**/

import Foundation
import Dispatch
import LoggerAPI
import Configuration
import CloudFoundryEnv
import CloudFoundryConfig
import KituraRequest
import SwiftMetrics
import SwiftMetricsKitura
import SwiftyJSON

fileprivate struct Stats {
  fileprivate var average: Double = 0
  fileprivate var count: Double = 0
  fileprivate var sum: Double = 0
}

fileprivate struct ThroughputStats {
  fileprivate var duration: Double = 0
  fileprivate var lastCalculateTime: TimeInterval = Date().timeIntervalSince1970 * 1000
  fileprivate var requestCount: Double = 0
  fileprivate var throughput: Double = 0
}

fileprivate struct Metrics {
  //holds the metrics we use for updates and used to create the metrics we send to the auto-scaling service
  fileprivate var latencyStats: Stats = Stats()
  fileprivate var httpStats: Stats = Stats()
  fileprivate var memoryStats: Stats = Stats()
  fileprivate var cpuStats: Stats = Stats()
  fileprivate var throughputStats: ThroughputStats = ThroughputStats()
}

fileprivate struct AverageMetrics {
  //Stores averages of metrics to send to the auto-scaling service
  fileprivate var dispatchQueueLatency: Double = 0
  fileprivate var responseTime: Double = 0
  fileprivate var memory: Double = 0
  fileprivate var cpu: Double = 0
  fileprivate var throughput : Double = 0
}

fileprivate struct Credentials {
  fileprivate var host = ""
  fileprivate var serviceID = ""
  fileprivate var appID = ""
  fileprivate var appName = ""
  fileprivate var instanceIndex = 0
  fileprivate var instanceId = ""
  fileprivate var authorization = ""
}

public class SwiftMetricsBluemix {

  var reportInterval: Int = 30
  // the number of s to wait between report thread runs

  var isAgentDisabled: Bool = false
  // can be turned on from the auto-scaling service in the refresh thread

  var enabledMetrics: [String] = []
  // list of metrics to collect (CPU, Memory, HTTP etc. Can be altered by the auto-scaling service in the refresh thread.

  fileprivate var metrics: Metrics = Metrics() //initialises to defaults above
  fileprivate var credentials: Credentials = Credentials()
  
  fileprivate let reportQueue = DispatchQueue(label: "SwiftMetricsBluemix Report Queue")
  fileprivate let refreshQueue = DispatchQueue(label: "SwiftMetricsBluemix Refresh Queue")

  public init(metricsToEnable: [String], swiftMetricsInstance: SwiftMetrics) {
    Log.entry("[Auto-Scaling Agent] initialization(\(metricsToEnable))")
    enabledMetrics = metricsToEnable
    if !self.initCredentials() {
      return
    }
    self.notifyStatus()
    self.refreshConfig()
    self.setMonitors(monitor: swiftMetricsInstance.monitor())
    reportQueue.async {
      self.snoozeStartReport()
    }
    refreshQueue.async {
      self.snoozeRefreshConfig()
    }
  }

  private func initCredentials() -> Bool {
    let configMgr = ConfigurationManager().load(.environmentVariables)
    // Find auto-scaling service using convenience method
    let scalingServ: Service? = configMgr.getServices(type: "Auto-Scaling").first
    guard let serv = scalingServ, let autoScalingService = AutoScalingService(withService: serv) else {
      Log.error("[Auto-Scaling Agent] Could not find Auto-Scaling service.")
      return false
    }
    Log.debug("[Auto-Scaling Agent] Found Auto-Scaling service: \(autoScalingService.name)")
    guard let app = configMgr.getApp() else {
      Log.error("[Auto-Scaling Agent] Could not get Cloud Foundry app metadata.")
      return false
    }
    
    // Assign unwrapped values
    self.credentials = Credentials(host: autoScalingService.url, serviceID: autoScalingService.serviceID,
        appID: autoScalingService.appID, appName: app.name, instanceIndex: app.instanceIndex, instanceId: app.instanceId,
        authorization: Data("\(autoScalingService.username):\(autoScalingService.password)".utf8).base64EncodedString())

    Log.debug("[Auto-scaling Agent] Authorisation: \(autoScalingService.username):\(autoScalingService.password)")
    return true
  }

  private func snoozeStartReport() {
    Log.debug("[Auto-Scaling Agent] waiting to startReport() for \(reportInterval) seconds...")
    sleep(UInt32(reportInterval))
    self.startReport()
    reportQueue.async {
      self.snoozeStartReport()
    }
  }

  private func snoozeRefreshConfig() {
    Log.debug("[Auto-Scaling Agent] waiting to refreshConfig() for 60 seconds...")
    sleep(UInt32(60))
    self.refreshConfig()
    refreshQueue.async {
      self.snoozeRefreshConfig()
    }
  }

  public convenience init(swiftMetricsInstance: SwiftMetrics) {
    self.init(metricsToEnable: ["CPU", "Memory", "Throughput", "ResponseTime", "DispatchQueueLatency"], swiftMetricsInstance: swiftMetricsInstance)
  }

  private func setMonitors(monitor: SwiftMonitor) {
    monitor.on({(mem: MemData) -> () in
      self.metrics.memoryStats.count += 1
      self.metrics.memoryStats.sum += Double(mem.applicationRAMUsed)
    })
    monitor.on({(cpu: CPUData) -> () in
      self.metrics.cpuStats.count += 1
      self.metrics.cpuStats.sum += Double(cpu.percentUsedByApplication) * 100.0;
    })
    monitor.on({(http: HTTPData) -> () in
      self.metrics.httpStats.count += 1
      self.metrics.httpStats.sum += http.duration;
      self.metrics.throughputStats.requestCount += 1;
    })
    monitor.on({(latency: LatencyData) -> () in
      self.metrics.latencyStats.count += 1
      self.metrics.latencyStats.sum += latency.duration
    })
  }

  private func startReport() {
    if (isAgentDisabled) {
      Log.verbose("[Auto-Scaling Agent] Agent is disabled by server")
      return
    } 

    let metricsToSend = calculateAverageMetrics()
    let sendObject = constructSendObject(metricsToSend: metricsToSend)
    sendMetrics(asOBJ : sendObject)

  }

  private func calculateAverageMetrics() ->  AverageMetrics {
    let latencyAverage: Double = (metrics.latencyStats.sum > 0 && metrics.latencyStats.count > 0) ? (metrics.latencyStats.sum / metrics.latencyStats.count) : 0.0
    metrics.latencyStats = Stats(average: latencyAverage, count: 0, sum: 0)

    let httpAverage = (metrics.httpStats.sum > 0 && metrics.httpStats.count > 0) ? (metrics.httpStats.sum / metrics.httpStats.count + metrics.latencyStats.average) : 0.0
    metrics.httpStats = Stats(average: httpAverage, count: 0, sum: 0)

    let memAverage = (metrics.memoryStats.sum > 0 && metrics.memoryStats.count > 0) ? (metrics.memoryStats.sum / metrics.memoryStats.count) : metrics.memoryStats.average;
    metrics.memoryStats = Stats(average: memAverage, count: 0, sum: 0)

    let cpuAverage = (metrics.cpuStats.sum > 0 && metrics.cpuStats.count > 0) ? (metrics.cpuStats.sum / metrics.cpuStats.count) : metrics.cpuStats.average;
    metrics.cpuStats = Stats(average: cpuAverage, count: 0, sum: 0)

    if (metrics.throughputStats.requestCount > 0) {
      let currentTime = Date().timeIntervalSince1970 * 1000
      let duration = currentTime - metrics.throughputStats.lastCalculateTime
      let throughput = metrics.throughputStats.requestCount / (duration / 1000)
      metrics.throughputStats = ThroughputStats(duration: duration, lastCalculateTime: currentTime, requestCount: 0, throughput: throughput)
    } else {
      let lastCalculateTime = metrics.throughputStats.lastCalculateTime
      metrics.throughputStats = ThroughputStats(duration: 0, lastCalculateTime: lastCalculateTime, requestCount: 0, throughput: 0)
    }

    let metricsToSend = AverageMetrics(dispatchQueueLatency: latencyAverage, responseTime: httpAverage, memory: memAverage,
      cpu: cpuAverage, throughput: metrics.throughputStats.throughput)
    Log.exit("[Auto-Scaling Agent] Average Metrics = \(metricsToSend)")
    return metricsToSend
  }

  private func constructSendMetric(group: String, name: String, value: Double, unit: String, timestamp: TimeInterval) -> [String:Any] {
    return ["category": "swift", "group": group, "name": name, "value": value, "unit": unit, "desc": "", "timestamp": timestamp]
  }

  private func constructSendObject(metricsToSend: AverageMetrics) -> [String:Any] {
    let timestamp = Date().timeIntervalSince1970 * 1000
    var metricsArray: [[String:Any]] = []

    for metric in enabledMetrics {
      switch (metric) {
        case "CPU":
          metricsArray.append(constructSendMetric(group: "ProcessCpuLoad", name: "ProcessCpuLoad",
              value: metricsToSend.cpu * 100.0, unit: "%%", timestamp: timestamp))
        case "Memory":
          metricsArray.append(constructSendMetric(group: "memory", name: "memory",
              value: metricsToSend.memory, unit: "Bytes", timestamp: timestamp))
        case "Throughput":
          metricsArray.append(constructSendMetric(group: "Web", name: "throughput",
              value: metricsToSend.throughput, unit: "", timestamp: timestamp))
        case "ResponseTime":
          metricsArray.append(constructSendMetric(group: "Web", name: "responseTime",
              value: metricsToSend.responseTime, unit: "ms", timestamp: timestamp))
        case "DispatchQueueLatency":
          metricsArray.append(constructSendMetric(group: "Web", name: "dispatchQueueLatency",
              value: metricsToSend.dispatchQueueLatency, unit: "ms", timestamp: timestamp))
        default:
          break
      }
    }

    let dict: [String:Any] = ["appId": credentials.appID, "appName": credentials.appName,
        "appType": "swift", "serviceId":  credentials.serviceID,
        "instanceIndex": credentials.instanceIndex, "instanceId": credentials.instanceId,
        "timestamp": timestamp, "metrics": metricsArray]

    Log.exit("[Auto-Scaling Agent] sendObject = \(dict)")
    return dict
  }

  private func sendMetrics(asOBJ : [String:Any]) {
    let sendMetricsPath = "\(credentials.host):443/services/agent/report"
    Log.debug("[Auto-scaling Agent] Attempting to send metrics to \(sendMetricsPath)")

    KituraRequest.request(.post, sendMetricsPath, parameters: asOBJ, encoding: JSONEncoding.default,
      headers: ["Content-Type":"application/json", "Authorization":"Basic \(credentials.authorization)"]
    ).response {
      request, response, data, error in
        Log.debug("[Auto-scaling Agent] sendMetrics:Request: \(request!)\n[Auto-scaling Agent] sendMetrics:Response: \(response!)")
        Log.debug("[Auto-scaling Agent] sendMetrics:Data: \(data!)\n[Auto-scaling Agent] sendMetrics:Error: \(error)")
    }
  }

  private func notifyStatus() {
    let notifyStatusPath = "\(credentials.host):443/services/agent/status/\(credentials.appID)"
    Log.debug("[Auto-scaling Agent] Attempting notifyStatus request to \(notifyStatusPath)")

    KituraRequest.request(.put, notifyStatusPath,
      headers: ["Authorization":"Basic \(credentials.authorization)"]
    ).response {
      request, response, data, error in
        Log.debug("[Auto-scaling Agent] notifyStatus:Request: \(request!)\n[Auto-scaling Agent] notifyStatus:Response: \(response!)")
        Log.debug("[Auto-scaling Agent] notifyStatus:Data: \(data)\n[Auto-scaling Agent] notifyStatus:Error: \(error)")
    }
  }


  // Read the config from the autoscaling service to see if any changes have been made
  private func refreshConfig() {
    let refreshConfigPath = "\(credentials.host):443/v1/agent/config/\(credentials.serviceID)/\(credentials.appID)?appType=swift"
    Log.debug("[Auto-scaling Agent] Attempting requestConfig request to \(refreshConfigPath)")
    KituraRequest.request(.get, refreshConfigPath,
      headers: ["Content-Type":"application/json", "Authorization":"Basic \(credentials.authorization)"]
    ).response {
      request, response, data, error in
        Log.debug("[Auto-scaling Agent] requestConfig:Request: \(request!)\n[Auto-scaling Agent] requestConfig:Response: \(response!)")
        Log.debug("[Auto-scaling Agent] requestConfig:Data: \(data!)\n[Auto-scaling Agent] requestConfig:Error: \(error)")
        Log.debug("[Auto-scaling Agent] requestConfig:Body: \(String(data: data!, encoding: .utf8))")
        self.updateConfiguration(response: data!)
    }
  }

  // Update local config from autoscaling service
  private func updateConfiguration(response: Data) {
    let jsonData = JSON(data: response)
    Log.debug("[Auto-scaling Agent] attempting to update configuration with \(jsonData)")
    guard let jsonInterval = jsonData["reportInterval"].int, let jsonMetrics = jsonData["metricsConfig"]["agent"].array else {
      isAgentDisabled = true
      return
    }
    isAgentDisabled = false
    reportInterval = jsonInterval
    enabledMetrics = jsonMetrics.map({$0.stringValue})
    Log.exit("[Auto-scaling Agent] Updated configuration - enabled metrics: \(enabledMetrics), report interval: \(reportInterval) seconds")
  }

}
