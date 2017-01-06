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
import Foundation

fileprivate struct HttpStats {
	fileprivate var count: Float = 0
	fileprivate var duration: Float = 0
	fileprivate var average: Float = 0
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
	fileprivate var httpStats: HttpStats = HttpStats()
	fileprivate var memoryStats: MemoryStats = MemoryStats()
	fileprivate var cpuStats: CPUStats = CPUStats()
	fileprivate var throughputStats: ThroughputStats = ThroughputStats()
}

fileprivate struct AverageMetrics {
	fileprivate var responseTime: Float = 0
	fileprivate var memory: Float = 0
	fileprivate var cpu: Float = 0
	fileprivate var throughput : Double = 0
}

public class AutoScalar {

	var reportIntervalID: Int = 0
	var refreshIntervalID: Int = 0
	var reportInterval: Int = 30000
	var refreshInterval: Int = 60000
	var isAgentEnabled: Bool = true
	var enabledMetrics: [String] = []
	let autoScalingRegex = "Auto(.*)Scaling"
	let sm: SwiftMetrics
	let monitor: SwiftMonitor
	fileprivate var metrics: Metrics = Metrics()

	public init(metricsToEnable: [String]) throws{
		enabledMetrics = metricsToEnable
		sm = try SwiftMetrics()
		monitor = sm.monitor()
		self.setMonitors()
		self.startReport()
		self.notifyStatus()
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
	}

	private func startReport() {
		do {
			guard let autoScalingService = try CloudFoundryEnv.getAppEnv().getServiceCreds(spec: autoScalingRegex) else {
				print("[Auto-Scaling Agent] Please bind auto-scaling service!")
				return
			}
			//report thread starts here
			if (!isAgentEnabled) {
				print("[Auto-Scaling Agent] Agent is disabled by server")
				print("\(autoScalingService)")
				return
			}
			let metricsToSend = calculateAverageMetrics()
			_ = constructSendObject(metricsToSend: metricsToSend)
			//sendMetrics(sendObject)
			//report thread ends here
		} catch {
			print("[Auto-Scaling Agent] Unable to determine if the auto-scaling service is bound!")
			return
		}
		//heartbeat thread starts here
			//refreshHeartBeat()
		//heartbeat thread ends here
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

	private func createMetricObject() {
	}

	private func constructSendObject(metricsToSend: AverageMetrics) {
		
		//for metric in enabledMetrics {
			//switch (metric) {
			//	case "CPU":
			//		print("")
			//}
		//}	
	}

	private func notifyStatus() {
		var serviceEnv: [String:Any] = [:]
		var agentUsername = "", agentPassword = "", appID = ""
		do {
			guard let autoScalingService = try CloudFoundryEnv.getAppEnv().getServiceCreds(spec: autoScalingRegex) else {
				print("[Auto-Scaling Agent] notifyStatus:serviceEnv is not found or empty")
				return
			}
			serviceEnv = autoScalingService
			guard let aU = autoScalingService["agentUsername"] else {
				print("[Auto-Scaling Agent] notifyStatus:serviceEnv.agentUsername is not found or empty")
				return
			}
			agentUsername = aU as! String
			guard let ap = autoScalingService["agentPassword"] else {
				print("[Auto-Scaling Agent] notifyStatus:serviceEnv.agentPassword is not found or empty")
				return
			}
			agentPassword = ap as! String
			guard let aI = autoScalingService["app_id"] else {
				print("[Auto-Scaling Agent] notifyStatus:serviceEnv.app_id is not found or empty")
				return
			}
			appID = aI as! String
		} catch {
			print("[Auto-Scaling Agent] notifyStatus:Unable to determine if the auto-scaling service is bound!")
			return
		}

		let host = serviceEnv["url"]!
		let auth = "\(agentUsername):\(agentPassword)"
		Log.info("[Auto-scaling Agent] Authorisation: \(auth)")
		let authorization = Data(auth.utf8).base64EncodedString()
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

		let serviceID = serviceEnv["service_id"]!
		let refreshConfigPath = "\(host):443/v1/agent/config/\(serviceID)/\(appID)?appType=nodejs"
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
		}
		
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
