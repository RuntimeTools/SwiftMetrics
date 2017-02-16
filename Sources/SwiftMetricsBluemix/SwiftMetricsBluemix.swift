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

fileprivate struct HttpStats {
  fileprivate var count: Double = 0
  fileprivate var duration: Double = 0
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
  fileprivate var httpStats: HttpStats = HttpStats()
  fileprivate var memoryStats: MemoryStats = MemoryStats()
  fileprivate var cpuStats: CPUStats = CPUStats()
  fileprivate var throughputStats: ThroughputStats = ThroughputStats()
}

fileprivate struct AverageMetrics {
  //Stores averages of metrics to send to the auto-scaling service
  fileprivate var responseTime: Double = 0
  fileprivate var memory: Float = 0
  fileprivate var cpu: Float = 0
  fileprivate var throughput : Double = 0
}

public class AutoScalar {

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
    Log.entry("[Auto-Scaling Agent] initialization(\(metricsToEnable))")
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

  private func initCredentials() -> Bool {
    let configMgr = ConfigurationManager().load(.environmentVariables)
    // Find auto-scaling service using convenience method
    let scalingServ: Service? = configMgr.getServices(type: autoScalingServiceLabel).first
    guard let serv = scalingServ, let autoScalingService = AutoScalingService(withService: serv) else {
      Log.error("[Auto-Scaling Agent] Could not find Auto-Scaling service.")
      return false
    }

    //// @Toby, @Matt - We are wondering if you ran into issues using the convenience
    //// method (see above) for getting services that match a given type (label).
    //// If you did, let us know and we can look into it. If there are not any issues,
    //// can you guys use the logic above instead of the code commented out below?
    ////
    // var scalingServ: Service? = nil
    // let services = configMgr.getServices()
    // for (_, service) in services {
    //    if service.label.hasPrefix(autoScalingServiceLabel) {
    //      Log.debug("[Auto-Scaling Agent] Found Auto-Scaling service: \(service.name)")
    //      scalingServ = service
    //      break
    //    }
    // }
    //
    // guard let serv = scalingServ, let autoScalingService = AutoScalingService(withService: serv) else {
    //   Log.error("[Auto-Scaling Agent] Could not create instance of Auto-Scaling service.")
    //   return false
    // }
    ////

    Log.debug("[Auto-Scaling Agent] Found Auto-Scaling service: \(autoScalingService.name)")

    // Assign unwrapped values
    self.host = autoScalingService.url
    self.serviceID = autoScalingService.serviceID
    self.appID = autoScalingService.appID
    self.agentPassword = autoScalingService.password
    self.agentUsername = autoScalingService.username

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
    self.init(metricsToEnable: ["CPU", "Memory", "Throughput", "ResponseTime"], swiftMetricsInstance: swiftMetricsInstance)
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
    metrics.httpStats.average = (metrics.httpStats.duration > 0 && metrics.httpStats.count > 0) ? (metrics.httpStats.duration / metrics.httpStats.count) : 0.0
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

    let metricsToSend = AverageMetrics(responseTime: metrics.httpStats.average,
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

    do {
      let jsonData = try JSONSerialization.data(withJSONObject: asOBJ, options: .prettyPrinted)
      let decoded = try JSONSerialization.jsonObject(with: jsonData, options: [])
      if let dictFromJSON = decoded as? [String:Any] {
        KituraRequest.request(.post,
          sendMetricsPath,
          parameters: dictFromJSON,
          encoding: JSONEncoding.default,
          headers: ["Content-Type":"application/json", "Authorization":"Basic \(authorization)"]
        ).response {
          request, response, data, error in
            Log.debug("[Auto-scaling Agent] sendMetrics:Request: \(request!)")
            Log.debug("[Auto-scaling Agent] sendMetrics:Response: \(response!)")
            Log.debug("[Auto-scaling Agent] sendMetrics:Data: \(data!)")
            Log.debug("[Auto-scaling Agent] sendMetrics:Error: \(error)")}
        }
    } catch {
      Log.warning("[Auto-Scaling Agent] \(error.localizedDescription)")
    }
  }

  private func notifyStatus() {
    let notifyStatusPath = "\(host):443/services/agent/status/\(appID)"
    Log.debug("[Auto-scaling Agent] Attempting notifyStatus request to \(notifyStatusPath)")
    KituraRequest.request(.put,
      notifyStatusPath,
      headers: ["Authorization":"Basic \(authorization)"]
    ).response {
      request, response, data, error in
        Log.debug("[Auto-scaling Agent] notifyStatus:Request: \(request!)")
        Log.debug("[Auto-scaling Agent] notifyStatus:Response: \(response!)")
        Log.debug("[Auto-scaling Agent] notifyStatus:Data: \(data)")
        Log.debug("[Auto-scaling Agent] notifyStatus:Error: \(error)")
    }
  }


  // Read the config from the autoscaling service to see if any changes have been made
  private func refreshConfig() {
    let refreshConfigPath = "\(host):443/v1/agent/config/\(serviceID)/\(appID)?appType=swift"
    Log.debug("[Auto-scaling Agent] Attempting requestConfig request to \(refreshConfigPath)")
    KituraRequest.request(.get,
      refreshConfigPath,
      headers: ["Content-Type":"application/json", "Authorization":"Basic \(authorization)"]
    ).response {
      request, response, data, error in
        Log.debug("[Auto-scaling Agent] requestConfig:Request: \(request!)")
        Log.debug("[Auto-scaling Agent] requestConfig:Response: \(response!)")
        Log.debug("[Auto-scaling Agent] requestConfig:Data: \(data!)")
        Log.debug("[Auto-scaling Agent] requestConfig:Error: \(error)")
        Log.debug("[Auto-scaling Agent] requestConfig:Body: \(String(data: data!, encoding: .utf8))")
        self.updateConfiguration(response: data!)
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
