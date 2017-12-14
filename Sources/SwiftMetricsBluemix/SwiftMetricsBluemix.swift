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
import SwiftyRequest
import SwiftMetrics
import SwiftMetricsKitura
import SwiftyJSON
import SwiftBAMDC

fileprivate struct HttpStats {
  fileprivate var count: Double = 0
  fileprivate var duration: Double = 0
  fileprivate var average: Double = 0
}

fileprivate struct LatencyStats {
  fileprivate var count: Double = 0
  fileprivate var sum: Double = 0
  fileprivate var average: Double = 0
}

fileprivate struct MemoryStats {
  fileprivate var count: Float = 0
  fileprivate var sum: Float = 0
  fileprivate var average: Float = 0
}

fileprivate struct CPUStats {
  fileprivate var count: Float = 0
  fileprivate var sum: Float = 0
  fileprivate var average: Float = 0
}

fileprivate struct ThroughputStats {
  fileprivate var duration: Double = 0
  fileprivate var lastCalculateTime: Double = Date().timeIntervalSince1970 * 1000
  fileprivate var requestCount: Double = 0
  fileprivate var throughput: Double = 0
}

fileprivate struct Metrics {
  //holds the metrics we use for updates and used to create the metrics we send to the auto-scaling service
  fileprivate var latencyStats: LatencyStats = LatencyStats()
  fileprivate var httpStats: HttpStats = HttpStats()
  fileprivate var memoryStats: MemoryStats = MemoryStats()
  fileprivate var cpuStats: CPUStats = CPUStats()
  fileprivate var throughputStats: ThroughputStats = ThroughputStats()
}

fileprivate struct AverageMetrics {
  //Stores averages of metrics to send to the auto-scaling service
  fileprivate var dispatchQueueLatency: Double = 0
  fileprivate var responseTime: Double = 0
  fileprivate var memory: Float = 0
  fileprivate var cpu: Float = 0
  fileprivate var throughput : Double = 0
}

public class SwiftMetricsBluemix {

  var SM:SwiftMetrics

  var reportInterval: Int = 30
  // the number of s to wait between report thread runs

  var availableMonitorInterval: Int = 5
  // the number of s to wait before checking if a monitor is available

  var configRefreshInterval: Int = 60
  // the number of s to wait between refresh thread runs

  var isAgentEnabled: Bool = true
  // can be turned off from the auto-scaling service in the refresh thread

  var enabledMetrics: [String] = []
  // list of metrics to collect (CPU, Memory, HTTP etc. Can be altered by the auto-scaling service in the refresh thread.

  let autoScalingServiceLabel = "Auto-Scaling"
  // used to find the AutoScaling service from the Cloud Foundry Application Environment

  let bamServiceLabel = "AvailabilityMonitoring.*"
  let bamDebugLabel = "IBAM_ENABLE_DC"
  // used to find the BAM service from the Cloud Foundry Application Environment

  fileprivate var metrics: Metrics = Metrics() //initialises to defaults above

  var agentUsername = ""
  var agentPassword = ""
  var appID = ""
  var host = ""
  var auth = ""
  var authorization = ""
  var serviceID = ""
  var appName = ""
  var instanceIndex = 0
  var instanceId = ""

  public init(metricsToEnable: [String], swiftMetricsInstance: SwiftMetrics) {

    self.SM = swiftMetricsInstance
    do {
       try self.detectBAMBinding(swiftMetricsInstance: self.SM)
    } catch {
        Log.error("[SwiftMetricsBluemix] exception thrown in detectBAMBinding")
    }

    Log.entry("[SwiftMetricsBluemix] initialization(\(metricsToEnable))")
    enabledMetrics = metricsToEnable

    if !self.initCredentials() {
      return
    }

    self.notifyStatus()
    self.refreshConfig()
    self.setMonitors(monitor: swiftMetricsInstance.monitor())
    DispatchQueue.global(qos: .background).async {
      self.snoozeStartReport()
    }
    DispatchQueue.global(qos: .background).async {
      self.snoozeRefreshConfig()
    }
  }

  private func detectBAMBinding(swiftMetricsInstance: SwiftMetrics) throws {
    let configMgr = ConfigurationManager().load(.environmentVariables)
    // Find BAM service using convenience method
    let bamServ: Service? = configMgr.getServices(type: bamServiceLabel).first

    if let dcEn = ProcessInfo.processInfo.environment[bamDebugLabel],  dcEn == "true" {
        Log.info("[SwiftMetricsBluemix] Detected BAM debug environment setting, enabling SwiftBAMDC")

        var _ = try SwiftDataCollector(swiftMetricsInstance: swiftMetricsInstance)
    }
    else if let bamS = bamServ {
        Log.info("[SwiftMetricsBluemix] Detected BAM Service \(bamS), enabling SwiftBAMDC ")
        var _ = try SwiftDataCollector(swiftMetricsInstance: swiftMetricsInstance)
    }
    else if let _ = ProcessInfo.processInfo.environment["IBAM_INGRESS_URL"] {
        Log.info("[SwiftMetricsBluemix] Detected IBAM_INGRESS_URL environment variable, enabling SwiftBAMDC ")
        var _ = try SwiftDataCollector(swiftMetricsInstance: swiftMetricsInstance)
    }
    else {
        Log.info("[SwiftMetricsBluemix] Could not find BAM service.")
        return
    }

  }

  private func initCredentials() -> Bool {
    let configMgr = ConfigurationManager().load(.environmentVariables)
    // Find auto-scaling service using convenience method
    guard let scalingServ: Service = configMgr.getServices(type: autoScalingServiceLabel).first else {
      Log.error("[Auto-Scaling Agent] Could not find Auto-Scaling service.")
      return false
    }

    // Assign unwrapped values
    guard let credentials = scalingServ.credentials,
      let host = credentials["url"] as? String,
      let serviceID = credentials["service_id"] as? String,
      let appID = credentials["app_id"] as? String,
      let agentPassword = credentials["agentPassword"] as? String,
      let agentUsername = credentials["agentUsername"] as? String else {        
        Log.error("[Auto-Scaling Agent] Could not obtain credentials for Auto-Scaling service.")
        return false
    }

    self.host = host
    self.serviceID = serviceID
    self.appID = appID
    self.agentPassword = agentPassword
    self.agentUsername = agentUsername

    Log.debug("[Auto-Scaling Agent] Found Auto-Scaling service: \(scalingServ.name)")

    guard let app = configMgr.getApp() else {
      Log.error("[Auto-Scaling Agent] Could not get Cloud Foundry app metadata.")
      return false
    }

    // Extract fields from App object
    appName = app.name
    instanceIndex = app.instanceIndex
    instanceId = app.instanceId

    auth = "\(agentUsername):\(agentPassword)"
    Log.debug("[Auto-scaling Agent] Authorisation: \(auth)")
    authorization = Data(auth.utf8).base64EncodedString()

    return true
  }

  private func snoozeStartReport() {
    Log.debug("[Auto-Scaling Agent] waiting to startReport() for \(reportInterval) seconds...")
    sleep(UInt32(reportInterval))
    self.startReport()
    DispatchQueue.global(qos: .background).async {
      self.snoozeStartReport()
    }
  }

  private func snoozeRefreshConfig() {
    Log.debug("[Auto-Scaling Agent] waiting to refreshConfig() for \(configRefreshInterval) seconds...")
    sleep(UInt32(configRefreshInterval))
    self.refreshConfig()
    DispatchQueue.global(qos: .background).async {
      self.snoozeRefreshConfig()
    }
  }

  public convenience init(swiftMetricsInstance: SwiftMetrics) {
    self.init(metricsToEnable: ["CPU", "Memory", "Throughput", "ResponseTime", "DispatchQueueLatency"], swiftMetricsInstance: swiftMetricsInstance)
  }

  private func setMonitors(monitor: SwiftMonitor) {
    monitor.on({(mem: MemData) -> () in
      self.metrics.memoryStats.count += 1
      let memValue = Float(mem.applicationRAMUsed)
      Log.debug("[Auto-scaling Agent] Memory value received \(memValue) bytes")
      self.metrics.memoryStats.sum += memValue
    })
    monitor.on({(cpu: CPUData) -> () in
      self.metrics.cpuStats.count += 1
      self.metrics.cpuStats.sum += cpu.percentUsedByApplication * 100;
    })
    monitor.on({(http: HTTPData) -> () in
      self.metrics.httpStats.count += 1
      self.metrics.httpStats.duration += http.duration;
      Log.debug("[Auto-scaling Agent] Http response time received \(http.duration) ")
      self.metrics.throughputStats.requestCount += 1;
    })
    monitor.on({(latency: LatencyData) -> () in
      self.metrics.latencyStats.count += 1
      self.metrics.latencyStats.sum += latency.duration
    })
  }

  private func startReport() {
    if (!isAgentEnabled) {
      Log.verbose("[Auto-Scaling Agent] Agent is disabled by server")
      return
    }

    let metricsToSend = calculateAverageMetrics()
    let sendObject = constructSendObject(metricsToSend: metricsToSend)
    sendMetrics(asOBJ : sendObject)

  }

  private func calculateAverageMetrics() ->  AverageMetrics {

    metrics.latencyStats.average = (metrics.latencyStats.sum > 0 && metrics.latencyStats.count > 0) ? (metrics.latencyStats.sum / metrics.latencyStats.count) : 0.0
    metrics.latencyStats.count = 0
    metrics.latencyStats.sum = 0

    metrics.httpStats.average = (metrics.httpStats.duration > 0 && metrics.httpStats.count > 0) ? (metrics.httpStats.duration / metrics.httpStats.count + metrics.latencyStats.average) : 0.0
    metrics.httpStats.count = 0;
    metrics.httpStats.duration = 0;

    metrics.memoryStats.average = (metrics.memoryStats.sum > 0 && metrics.memoryStats.count > 0) ? (metrics.memoryStats.sum / metrics.memoryStats.count) : metrics.memoryStats.average;
    metrics.memoryStats.count = 0;
    metrics.memoryStats.sum = 0;

    metrics.cpuStats.average = (metrics.cpuStats.sum > 0 && metrics.cpuStats.count > 0) ? (metrics.cpuStats.sum / metrics.cpuStats.count) : metrics.cpuStats.average;
    metrics.cpuStats.count = 0;
    metrics.cpuStats.sum = 0;

    if (metrics.throughputStats.requestCount > 0) {
      let currentTime = Date().timeIntervalSince1970 * 1000
      let duration = currentTime - metrics.throughputStats.lastCalculateTime
      metrics.throughputStats.throughput = metrics.throughputStats.requestCount / (duration / 1000)
      metrics.throughputStats.lastCalculateTime = currentTime
      metrics.throughputStats.duration = duration
    } else {
      metrics.throughputStats.throughput = 0
      metrics.throughputStats.duration = 0
    }
    metrics.throughputStats.requestCount = 0

    let metricsToSend = AverageMetrics(
      dispatchQueueLatency: metrics.latencyStats.average,
      responseTime: metrics.httpStats.average,
      memory: metrics.memoryStats.average,
      cpu: metrics.cpuStats.average,
      throughput: metrics.throughputStats.throughput
    )
    Log.exit("[Auto-Scaling Agent] Average Metrics = \(metricsToSend)")
    return metricsToSend
  }

  private func constructSendObject(metricsToSend: AverageMetrics) -> [String:Any] {
    let timestamp = Date().timeIntervalSince1970 * 1000
    var metricsArray: [[String:Any]] = []

    for metric in enabledMetrics {
      switch (metric) {
        case "CPU":
          var metricDict = [String:Any]()
          metricDict["category"] = "swift"
          metricDict["group"] = "ProcessCpuLoad"
          metricDict["name"] = "ProcessCpuLoad"
          metricDict["value"] = Double(metricsToSend.cpu) * 100.0
          metricDict["unit"] = "%%"
          metricDict["desc"] = ""
          metricDict["timestamp"] = timestamp
          metricsArray.append(metricDict)
        case "Memory":
          var metricDict = [String:Any]()
          metricDict["category"] = "swift"
          metricDict["group"] = "memory"
          metricDict["name"] = "memory"
          metricDict["value"] = Double(metricsToSend.memory)
          metricDict["unit"] = "Bytes"
          metricDict["desc"] = ""
          metricDict["timestamp"] = timestamp
          metricsArray.append(metricDict)
        case "Throughput":
          var metricDict = [String:Any]()
          metricDict["category"] = "swift"
          metricDict["group"] = "Web"
          metricDict["name"] = "throughput"
          metricDict["value"] = Double(metricsToSend.throughput)
          metricDict["unit"] = ""
          metricDict["desc"] = ""
          metricDict["timestamp"] = timestamp
          metricsArray.append(metricDict)
        case "ResponseTime":
          var metricDict = [String:Any]()
          metricDict["category"] = "swift"
          metricDict["group"] = "Web"
          metricDict["name"] = "responseTime"
          metricDict["value"] = Double(metricsToSend.responseTime)
          metricDict["unit"] = "ms"
          metricDict["desc"] = ""
          metricDict["timestamp"] = timestamp
          metricsArray.append(metricDict)
        case "DispatchQueueLatency":
          var metricDict = [String:Any]()
          metricDict["category"] = "swift"
          metricDict["group"] = "Web"
          metricDict["name"] = "dispatchQueueLatency"
          metricDict["value"] = Double(metricsToSend.dispatchQueueLatency)
          metricDict["unit"] = "ms"
          metricDict["desc"] = ""
          metricDict["timestamp"] = timestamp
          metricsArray.append(metricDict)
        default:
          break
      }
    }

    var dict = [String:Any]()
    dict["appId"] = appID
    dict["appName"] = appName
    dict["appType"] = "swift"
    dict["serviceId"] = serviceID
    dict["instanceIndex"] = instanceIndex
    dict["instanceId"] = instanceId
    dict["timestamp"] = timestamp
    dict["metrics"] = metricsArray

    Log.exit("[Auto-Scaling Agent] sendObject = \(dict)")
    return dict
  }

  private func sendMetrics(asOBJ : [String:Any]) {
    let sendMetricsPath = "\(host):443/services/agent/report"
    Log.debug("[Auto-scaling Agent] Attempting to send metrics to \(sendMetricsPath)")

    
    let request = RestRequest(method: .post, url: sendMetricsPath)
    request.headerParameters = ["Content-Type":"application/json", "Authorization":"Basic \(authorization)"]
    do {
        request.messageBody = try JSONSerialization.data(withJSONObject: asOBJ, options: .prettyPrinted)
    } catch {
            print("Error converting input to JSON object to post.")
    }
    request.response { (data, response, error) in
        Log.debug("[Auto-scaling Agent] sendMetrics:Request: \(String(describing:request))")
        Log.debug("[Auto-scaling Agent] sendMetrics:Response: \(String(describing:response))")
        Log.debug("[Auto-scaling Agent] sendMetrics:Data: \(String(describing:data))")
        Log.debug("[Auto-scaling Agent] sendMetrics:Error: \(String(describing: error))")
    }
    
  }

  private func notifyStatus() {
    let notifyStatusPath = "\(host):443/services/agent/status/\(appID)"
    Log.debug("[Auto-scaling Agent] Attempting notifyStatus request to \(notifyStatusPath)")
    
    let request = RestRequest(method: .put, url: notifyStatusPath)
    request.headerParameters = ["Authorization":"Basic \(authorization)"]
    request.response { (data, response, error) in
        Log.debug("[Auto-scaling Agent] notifyStatus:Request: \(String(describing:request))")
        Log.debug("[Auto-scaling Agent] notifyStatus:Response: \(String(describing:response))")
        Log.debug("[Auto-scaling Agent] notifyStatus:Data: \(String(describing: data))")
        Log.debug("[Auto-scaling Agent] notifyStatus:Error: \(String(describing: error))")
    }
    
  }


  // Read the config from the autoscaling service to see if any changes have been made
  private func refreshConfig() {
    let refreshConfigPath = "\(host):443/v1/agent/config/\(serviceID)/\(appID)?appType=swift"
    Log.debug("[Auto-scaling Agent] Attempting requestConfig request to \(refreshConfigPath)")

    let request = RestRequest(method: .get, url: refreshConfigPath)
    request.headerParameters = ["Content-Type":"application/json", "Authorization":"Basic \(authorization)"]
    request.response { (data, response, error) in
        Log.debug("[Auto-scaling Agent] requestConfig:Request: \(String(describing:request))")
        Log.debug("[Auto-scaling Agent] requestConfig:Response: \(String(describing:response))")
        Log.debug("[Auto-scaling Agent] requestConfig:Data: \(String(describing: data))")
        Log.debug("[Auto-scaling Agent] requestConfig:Error: \(String(describing: error))")
        Log.debug("[Auto-scaling Agent] requestConfig:Body: \(String(describing: data))")
        if let responseData = data {
            self.updateConfiguration(response: responseData)
        } else {
            print("Error updating configuration. Data doesn't exist.")
        }
    }
    
  }

  // Update local config from autoscaling service
  private func updateConfiguration(response: Data) {
    let jsonData = JSON(data: response)
    Log.debug("[Auto-scaling Agent] attempting to update configuration with \(jsonData)")
    if (jsonData == nil) {
      isAgentEnabled = false
      return
    }
    if (jsonData["metricsConfig"]["agent"] == nil) {
      isAgentEnabled = false
      return
    } else {
      isAgentEnabled = true
      enabledMetrics=jsonData["metricsConfig"]["agent"].arrayValue.map({$0.stringValue})
    }
    reportInterval=jsonData["reportInterval"].intValue
    Log.exit("[Auto-scaling Agent] Updated configuration - enabled metrics: \(enabledMetrics), report interval: \(reportInterval) seconds")
  }

}
