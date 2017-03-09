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
import SwiftMetricsKitura
import SwiftMetricsBluemix
import SwiftMetrics
import SwiftyJSON
import KituraNet
import KituraWebSocket
import Foundation
import Configuration
import CloudFoundryConfig
import Dispatch

struct HTTPAggregateData: SMData {
  public var timeOfRequest: Int = 0
  public var url: String = ""
  public var longest: Double = 0
  public var average: Double = 0
  public var total: Int = 0
}
var router = Router()
public class SwiftMetricsDash {

    var monitor:SwiftMonitor
    var SM:SwiftMetrics
    var service:SwiftMetricsService

    public convenience init(swiftMetricsInstance : SwiftMetrics) throws {
       try self.init(swiftMetricsInstance : swiftMetricsInstance , endpoint: nil)
    }

    public init(swiftMetricsInstance : SwiftMetrics , endpoint: Router!) throws {
        // default to use passed in Router
        var create = false

        if endpoint == nil {
            create = true
        } else {
            router =  endpoint
        }
         self.SM = swiftMetricsInstance
        _ = SwiftMetricsKitura(swiftMetricsInstance: SM)
        self.monitor = SM.monitor()
        self.service = SwiftMetricsService(monitor: monitor)
        WebSocket.register(service: self.service, onPath: "swiftmetrics-dash")

        try startServer(createServer: create, router: router)
    }

    func startServer(createServer: Bool, router: Router) throws {
        let fm = FileManager.default
        let currentDir = fm.currentDirectoryPath
        var workingPath = ""
        if currentDir.contains(".build") {
            //we're below the Packages directory
            workingPath = currentDir
        } else {
         	//we're above the Packages directory
            workingPath = CommandLine.arguments[0]
        }
        let i = workingPath.range(of: ".build")
        var packagesPath = ""
        if i == nil {
            // we could be in bluemix
            packagesPath="/home/vcap/app/"
        } else {
            packagesPath = workingPath.substring(to: i!.lowerBound)
        }
        packagesPath.append("Packages/")
        let dirContents = try fm.contentsOfDirectory(atPath: packagesPath)
        for dir in dirContents {
            if dir.contains("SwiftMetrics") {
                packagesPath.append("\(dir)/public")
            }
        }
        router.all("/swiftmetrics-dash", middleware: StaticFileServer(path: packagesPath))

        if createServer {
            let configMgr = ConfigurationManager().load(.environmentVariables)
            Kitura.addHTTPServer(onPort: configMgr.port, with: router)
            print("SwiftMetricsDash : Starting on port \(configMgr.port)")
            Kitura.run()
        }
 	}




}
class SwiftMetricsService: WebSocketService {

    private var connections = [String: WebSocketConnection]()
    var httpAggregateData: HTTPAggregateData = HTTPAggregateData()
    var httpURLData:[String:(totalTime:Double, numHits:Double)] = [:]
    let httpURLsQueue = DispatchQueue(label: "httpURLsQueue")
    let httpQueue = DispatchQueue(label: "httpStoreQueue")
    var monitor:SwiftMonitor

    public init(monitor: SwiftMonitor) {
        self.monitor = monitor
        monitor.on(sendCPU)
        monitor.on(sendMEM)
        monitor.on(storeHTTP)
        gethttpRequest()
      //  gethttpURLs()
  }



    func sendCPU(cpu: CPUData) {
        let cpuLine = JSON(["topic":"cpu", "payload":["time":"\(cpu.timeOfSample)","process":"\(cpu.percentUsedByApplication)","system":"\(cpu.percentUsedBySystem)"]])

        for (_,connection) in connections {
            if let messageToSend = cpuLine.rawString() {
                connection.send(message: messageToSend)
            }
        }

    }


    func sendMEM(mem: MemData) {

        let memLine = JSON(["topic":"memory","payload":[
                "time":"\(mem.timeOfSample)",
                "physical":"\(mem.applicationRAMUsed)",
                "physical_used":"\(mem.totalRAMUsed)"
                ]])

        for (_,connection) in connections {
            if let messageToSend = memLine.rawString() {
                connection.send(message: messageToSend)
            }
        }
    }

    func sendHTTP(myhttp: HTTPData) {
        let httpLine = JSON(["topic":"http","payload":["time":"\(myhttp.timeOfRequest)","url":"\(myhttp.url)","duration":"\(myhttp.duration)","method":"\(myhttp.requestMethod)","statusCode":"\(myhttp.statusCode)"]])

        for (_,connection) in connections {
            if let messageToSend = httpLine.rawString() {
                connection.send(message: messageToSend)
            }
        }

    }

    public func connected(connection: WebSocketConnection) {
        connections[connection.id] = connection
        getenvRequest()
    }

    public func disconnected(connection: WebSocketConnection, reason: WebSocketCloseReasonCode){}

    public func received(message: Data, from : WebSocketConnection){}

    public func received(message: String, from : WebSocketConnection){
        print("SwiftMetricsService -- \(message)")
    }


    public func getenvRequest()  {
        var commandLine = ""
        var hostname = ""
        var os = ""
        var numPar = ""

        for (param, value) in self.monitor.getEnvironmentData() {
            switch param {
                case "command.line":
                    commandLine = value
                    break
                case "environment.HOSTNAME":
                    hostname = value
                    break
                case "os.arch":
                    os = value
                    break
                case "number.of.processors":
                    numPar = value
                    break
                default:
                    break
             }
        }


        let envLine = JSON(["topic":"env","payload":[
                ["Parameter":"Command Line","Value":"\(commandLine)"],
                ["Parameter":"Hostname","Value":"\(hostname)"],
                ["Parameter":"Number of Processors","Value":"\(numPar)"],
                ["Parameter":"OS Architecture","Value":"\(os)"]
                ]])

        for (_,connection) in connections {
            if let messageToSend = envLine.rawString() {
                connection.send(message: messageToSend)
            }
        }
    }

    public func storeHTTP(myhttp: HTTPData) {
    	httpQueue.async {
            if self.httpAggregateData.total == 0 {
                self.httpAggregateData.total = 1
                self.httpAggregateData.timeOfRequest = myhttp.timeOfRequest
                self.httpAggregateData.url = myhttp.url
                self.httpAggregateData.longest = myhttp.duration
                self.httpAggregateData.average = myhttp.duration
            } else {
              let oldTotalAsDouble:Double = Double(self.httpAggregateData.total)
              let newTotal = self.httpAggregateData.total + 1
              self.httpAggregateData.total = newTotal
              self.httpAggregateData.average = (self.httpAggregateData.average * oldTotalAsDouble + myhttp.duration) / Double(newTotal)
              if (myhttp.duration > self.httpAggregateData.longest) {
                self.httpAggregateData.longest = myhttp.duration
                self.httpAggregateData.url = myhttp.url
              }
            }
        }
        httpURLsQueue.async {
            let urlTuple = self.httpURLData[myhttp.url]
            if(urlTuple != nil) {
                let averageResponseTime = urlTuple!.0
                let hits = urlTuple!.1
                // Recalculate the average
                self.httpURLData.updateValue(((averageResponseTime * hits + myhttp.duration)/(hits + 1), hits + 1), forKey: myhttp.url)
            } else {
                self.httpURLData.updateValue((myhttp.duration, 1), forKey: myhttp.url)
            }
        }
    }

    func gethttpRequest()  {
        sleep(UInt32(2))
        httpQueue.async {
            do {
                if self.httpAggregateData.total > 0 {
                    let httpLine = JSON([
                    "topic":"http","payload":[
                        "time":"\(self.httpAggregateData.timeOfRequest)",
                        "url":"\(self.httpAggregateData.url)",
                        "longest":"\(self.httpAggregateData.longest)",
                        "average":"\(self.httpAggregateData.average)",
                        "total":"\(self.httpAggregateData.total)"]])

                        for (_,connection) in self.connections {
                            if let messageToSend = httpLine.rawString() {
                                connection.send(message: messageToSend)
                            }
                        }
                    self.httpAggregateData = HTTPAggregateData()
                }
            }
        }
        DispatchQueue.global(qos: .background).async {
          self.gethttpRequest()
        }
    }

    func gethttpURLs() {
        sleep(UInt32(2))
        httpURLsQueue.async {
            var responseData:[JSON] = []
            for (key, value) in self.httpURLData {
                let json = JSON(["url":key, "averageResponseTime": value.0])
                //if let appendString = json.rawString() {
                    //responseData += appendString
                    responseData.append(json)
                //        print("ursl is \(responseData)")
              //  }
            }

            let httpURLLine = JSON(["topic":"httpURLs","payload":[responseData]])
            print("httpURLLine is \(httpURLLine)")
            for (_,connection) in self.connections {
                if let messageToSend = httpURLLine.rawString() {
                    connection.send(message: messageToSend)
                }
            }
        }
        DispatchQueue.global(qos: .background).async {
          self.gethttpURLs()
        }
    }

}
