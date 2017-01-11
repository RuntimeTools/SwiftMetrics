/**
* Copyright IBM Corporation 2016
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

import Kitura
import KituraRequest
import SwiftyJSON
import LoggerAPI
import CloudFoundryEnv
import SwiftMetrics
import SwiftMetricsKitura
import Foundation
import Dispatch

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
    fileprivate var lastCalculateTime: Double = NSDate().timeIntervalSince1970
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
    
    var reportInterval: Int = 10
    // the number of ms to wait between report thread runs
    
    var configRefreshIntervalID: Int = 0
    //the thread id for the refresh, or heartbeat, thread, so we can cancel it. May not be required in Swift.
     
    var configRefreshInterval: Int = 60
    // the number of ms to wait between refresh thread runs
    
    var isAgentEnabled: Bool = true
    // can be turned off from the auto-scaling service in the refresh thread
    
    var enabledMetrics: [String] = []
    // list of metrics to collect (CPU, Memory, HTTP etc. Can be altered by the auto-scaling service in the refresh thread.
    
    let autoScalingRegex = "Auto(.*)Scaling"
    // used to find the AutoScaling service from the Cloud Foundry Application Environment
    
    let sm: SwiftMetrics
    let monitor: SwiftMonitor
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

    public init(metricsToEnable: [String]) throws{
        enabledMetrics = metricsToEnable
        sm = try SwiftMetrics()
        monitor = sm.monitor()
        if !self.initCredentials() {
            return
        }
        self.setMonitors()
        self.notifyStatus()
        self.refreshConfig()
        
        DispatchQueue.global(qos: .background).async {
            self.snoozeStartReport()
        }
        DispatchQueue.global(qos: .background).async {
            self.snoozeRefreshConfig()
        }
    }

    private func initCredentials() ->  Bool {
        do {
            let appEnv = try CloudFoundryEnv.getAppEnv() 
            
            guard let autoScalingService =  appEnv.getServiceCreds(spec: autoScalingRegex) else {
                print("[Auto-Scaling Agent] Please bind auto-scaling service!")
                return false
            }

            guard let aU = autoScalingService["agentUsername"] else {
                print("[Auto-Scaling Agent] sendMetrics:serviceEnv.agentUsername is not found or empty")
                return false
            }
            agentUsername = aU as! String
            guard let ap = autoScalingService["agentPassword"] else {
                print("[Auto-Scaling Agent] sendMetrics:serviceEnv.agentPassword is not found or empty")
                return false
            }
            agentPassword = ap as! String
            guard let aI = autoScalingService["app_id"] else {
                print("[Auto-Scaling Agent] sendMetrics:serviceEnv.app_id is not found or empty")
                return false
            }

            appID = aI as! String
       
            guard let hostTemp = autoScalingService["url"] else {
                print("[Auto-Scaling Agent] sendMetrics:serviceEnv.url is not found or empty")
                return false
            }

            host = hostTemp as! String
            
            guard let serviceIDTemp = autoScalingService["service_id"] else {
                print("[Auto-Scaling Agent] sendMetrics:serviceEnv.url is not found or empty")
                return false
            }
       
            serviceID = serviceIDTemp as! String

            appName = appEnv.getApp()!.name
     
            instanceIndex = appEnv.getApp()!.instanceIndex
            
            instanceId = appEnv.getApp()!.instanceId 
       
            auth = "\(agentUsername):\(agentPassword)"
            Log.info("[Auto-scaling Agent] Authorisation: \(auth)")
            authorization = Data(auth.utf8).base64EncodedString()
        } catch {
            print("[Auto-Scaling Agent] CloudFoundryEnv.getAppEnv() threw exception")
            return false
        }
        
        return true
    }
    
    private func snoozeStartReport() {
        sleep(UInt32(reportInterval))
        self.startReport()
        DispatchQueue.global(qos: .background).async {
            self.snoozeStartReport()
        }
    }


    private func snoozeRefreshConfig() {
        sleep(UInt32(configRefreshInterval))
        self.refreshConfig()
        DispatchQueue.global(qos: .background).async {
            self.snoozeRefreshConfig()
        }
    }



    public convenience init() throws {
        try self.init(metricsToEnable: ["CPU", "Memory", "Throughput"])
    }

    private func setMonitors() {
        monitor.on({(mem: MemData) -> () in
            self.metrics.memoryStats.count += 1
            self.metrics.memoryStats.sum += Float(mem.totalRAMUsed)
        })
        monitor.on({(cpu: CPUData) -> () in
            self.metrics.cpuStats.count += 1
            self.metrics.cpuStats.sum += cpu.percentUsedByApplication * 100;
        })
        monitor.on({(http: HTTPData) -> () in
            self.metrics.httpStats.count += 1
            self.metrics.httpStats.duration += http.duration;
            self.metrics.throughputStats.requestCount += 1;
        })
    }

    private func startReport() {
        if (!isAgentEnabled) {
            print("[Auto-Scaling Agent] Agent is disabled by server")
            return
        }
         
        let metricsToSend = calculateAverageMetrics()
        _ = constructSendObject(metricsToSend: metricsToSend)
        sendMetrics(asOBJ : constructSendObject(metricsToSend: metricsToSend))

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
            let currentTime = NSDate().timeIntervalSince1970
            let duration = currentTime - metrics.throughputStats.lastCalculateTime
            metrics.throughputStats.throughput = metrics.throughputStats.requestCount / (duration / 1000)
            metrics.throughputStats.lastCalculateTime = currentTime
            metrics.throughputStats.duration = duration
        } else {
            metrics.throughputStats.throughput = 0
            metrics.throughputStats.duration = 0
        }
        metrics.throughputStats.requestCount = 0

        return AverageMetrics(responseTime: metrics.httpStats.average,
                    memory: metrics.memoryStats.average,
                    cpu: metrics.cpuStats.average,
                    throughput: metrics.throughputStats.throughput
        )
    }

    private func constructSendObject(metricsToSend: AverageMetrics) -> [String:Any] {
        let timestamp = NSDate().timeIntervalSince1970
        var metricDict = [String:Any]()
        var metricsArray = [metricDict]
        
        for metric in enabledMetrics {
            switch (metric) {
                case "CPU":
                    metricDict["category"] = "nodejs"
                    metricDict["group"] = "ProcessCpuLoad"
                    metricDict["name"] = "ProcessCpuLoad"
                    metricDict["value"] = Double(metricsToSend.cpu) * 100.0
                    metricDict["unit"] = "%%"
                    metricDict["desc"] = ""
                    metricsArray.append(metricDict)
              case "Memory":
                    metricDict["category"] = "nodejs"
                    metricDict["group"] = "memory"
                    metricDict["name"] = "memory"
                    metricDict["value"] = Double(metricsToSend.memory)
                    metricDict["unit"] = "Bytes"
                    metricDict["desc"] = ""
                    metricsArray.append(metricDict)
              case "Throughput":
                    metricDict["category"] = "nodejs"
                    metricDict["group"] = "Web"
                    metricDict["name"] = "throughput"
                    metricDict["value"] = Double(metricsToSend.throughput)
                    metricDict["unit"] = ""
                    metricDict["desc"] = ""
                    metricsArray.append(metricDict)
              default:
                    break
            }
        }

        var dict = [String:Any]()
        dict["appId"] = appID
        dict["appName"] = appName
        dict["appType"] = "nodejs"
        dict["serviceId"] = serviceID
        dict["instanceIndex"] = instanceIndex
        dict["instanceId"] = instanceId
        dict["timestamp"] = timestamp
        dict["metrics"] = metricsArray

        return dict
    }

    private func sendMetrics(asOBJ : [String:Any]) { 
        let sendMetricsPath = "\(host):443/services/agent/report"
        Log.info("[Auto-scaling Agent] Attempting to send metrics to \(sendMetricsPath)")

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
                            Log.info("[Auto-scaling Agent] sendMetrics:Request: \(request!)")
                            Log.info("[Auto-scaling Agent] sendMetrics:Response: \(response!)")
                            Log.info("[Auto-scaling Agent] sendMetrics:Data: \(data!)")
                            Log.info("[Auto-scaling Agent] sendMetrics:Error: \(error)")}
            }
        } catch {
            print("[Auto-Scaling Agent] \(error.localizedDescription)")
        }
    }

    private func notifyStatus() {
        let notifyStatusPath = "\(host):443/services/agent/status/\(appID)"
        Log.info("[Auto-scaling Agent] Attempting notifyStatus request to \(notifyStatusPath)")
        KituraRequest.request(.put,
                notifyStatusPath,
                headers: ["Authorization":"Basic \(authorization)"]
                ).response {
            request, response, data, error in
                Log.info("[Auto-scaling Agent] notifyStatus:Request: \(request!)")
                Log.info("[Auto-scaling Agent] notifyStatus:Response: \(response!)")
                Log.info("[Auto-scaling Agent] notifyStatus:Data: \(data)")
                Log.info("[Auto-scaling Agent] notifyStatus:Error: \(error)")
        }
        
    }


    // Read the config from the autoscaling service to see if any changes have been made    
    private func refreshConfig() {
        let refreshConfigPath = "\(host):443/v1/agent/config/\(serviceID)/\(appID)?appType=nodejs" //change to swift when supported
        Log.info("[Auto-scaling Agent] Attempting requestConfig request to \(refreshConfigPath)")
        KituraRequest.request(.get,
                refreshConfigPath,
                headers: ["Content-Type":"application/json", "Authorization":"Basic \(authorization)"]
                ).response {
            request, response, data, error in
                Log.info("[Auto-scaling Agent] requestConfig:Request: \(request!)")
                Log.info("[Auto-scaling Agent] requestConfig:Response: \(response!)")
                Log.info("[Auto-scaling Agent] requestConfig:Data: \(data!)")
                Log.info("[Auto-scaling Agent] requestConfig:Error: \(error)")

                Log.info("[Auto-scaling Agent] requestConfig:Body: \(String(data: data!, encoding: .utf8))")
                self.updateConfiguration(response: data!)
        }
    }

    // Update local config from autoscaling service
    private func updateConfiguration(response: Data) {

            let jsonData = JSON(data: response)
            if (jsonData == nil) {
                isAgentEnabled = false
            }
            if (jsonData["metricsConfig"]["agent"] == nil) {
                isAgentEnabled = false
            }            
            enabledMetrics=jsonData["metricsConfig"]["agent"].arrayValue.map({$0.stringValue})
            reportInterval=jsonData["reportInterval"].intValue
      
    }
        
}

public class Controller {

  let router: Router
  let appEnv: AppEnv
  let asa   : AutoScalar?

  var port: Int {
    get { return appEnv.port }
  }

  var url: String {
    get { return appEnv.url }
  }

  init() throws {
    appEnv = try CloudFoundryEnv.getAppEnv()

    if (!appEnv.isLocal) {
        Log.info("[Auto-scaling Agent] Remote connection - starting agent")
        asa = try AutoScalar()
    } else {
        Log.info("[Auto-scaling Agent] Local connection - not starting")
        asa = nil
    }

    // All web apps need a Router instance to define routes
    router = Router()

    // Serve static content from "public"
    router.all("/", middleware: StaticFileServer())

    // Basic GET request
    router.get("/hello", handler: getHello)

    // Basic POST request
    router.post("/hello", handler: postHello)

    // JSON Get request
    router.get("/json", handler: getJSON)

    // JSON Get request
    router.get("/autoparams", handler: getAutoParams)

  }

  public func getHello(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
    Log.debug("GET - /hello route handler...")
    response.headers["Content-Type"] = "text/plain; charset=utf-8"
    try response.status(.OK).send("Hello from Kitura-Starter!").end()
  }

  public func postHello(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
    Log.debug("POST - /hello route handler...")
    response.headers["Content-Type"] = "text/plain; charset=utf-8"
    if let name = try request.readString() {
      try response.status(.OK).send("Hello \(name), from Kitura-Starter!").end()
    } else {
      try response.status(.OK).send("Kitura-Starter received a POST request!").end()
    }
  }

  public func getJSON(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
    Log.debug("GET - /json route handler...")
    response.headers["Content-Type"] = "application/json; charset=utf-8"
    var jsonResponse = JSON([:])
    jsonResponse["framework"].stringValue = "Kitura"
    jsonResponse["applicationName"].stringValue = "Kitura-Starter"
    jsonResponse["company"].stringValue = "IBM"
    jsonResponse["organization"].stringValue = "Swift @ IBM"
    jsonResponse["location"].stringValue = "Austin, Texas"
    try response.status(.OK).send(json: jsonResponse).end()
  }

  public func getAutoParams(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
    Log.debug("GET - /autoparams route handler...")
    response.headers["Content-Type"] = "application/json; charset=utf-8"
    var jsonResponse = JSON([:])
    jsonResponse["getApplicationEnv"].stringValue = "\(appEnv)"
    let regex = "Auto(.*)Scaling"
    jsonResponse["getServiceEnv"].stringValue = "\(appEnv.getServiceCreds(spec: regex))"
    jsonResponse["parseUrlToHostPort"].stringValue = "\(appEnv.url):\(appEnv.port)"
    try response.status(.OK).send(json: jsonResponse).end()
  }

}
