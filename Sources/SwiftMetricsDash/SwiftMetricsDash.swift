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
    var createServer: Bool = false

    public convenience init(swiftMetricsInstance : SwiftMetrics) throws {
       try self.init(swiftMetricsInstance : swiftMetricsInstance , endpoint: nil)
    }

    public init(swiftMetricsInstance : SwiftMetrics , endpoint: Router!) throws {
        // default to use passed in Router
        if endpoint == nil {
            self.createServer = true
        } else {
            router =  endpoint
        }
        self.SM = swiftMetricsInstance
        _ = SwiftMetricsKitura(swiftMetricsInstance: SM)
        self.monitor = SM.monitor()
        self.service = SwiftMetricsService(monitor: monitor)
        WebSocket.register(service: self.service, onPath: "swiftmetrics-dash")

        try startServer(router: router)
    }

    deinit {
        if self.createServer {
            Kitura.stop()
        }
    }

    func startServer(router: Router) throws {
      router.all("/swiftmetrics-dash", middleware: StaticFileServer(path: self.SM.localSourceDirectory + "/public"))
      
        if self.createServer {
            let configMgr = ConfigurationManager().load(.environmentVariables)
            Kitura.addHTTPServer(onPort: configMgr.port, with: router)
            print("SwiftMetricsDash : Starting on port \(configMgr.port)")
            Kitura.start()
        }
     }
}
class SwiftMetricsService: WebSocketService {

    private var connections = [String: WebSocketConnection]()
    var httpAggregateData: HTTPAggregateData = HTTPAggregateData()
    var httpURLData:[String:(totalTime:Double, numHits:Double)] = [:]
    let httpURLsQueue = DispatchQueue(label: "httpURLsQueue")
    let httpQueue = DispatchQueue(label: "httpStoreQueue")
    let jobsQueue = DispatchQueue(label: "jobsQueue")
    var monitor:SwiftMonitor


    public init(monitor: SwiftMonitor) {
        self.monitor = monitor
        monitor.on(sendCPU)
        monitor.on(sendMEM)
        monitor.on(storeHTTP)
        sendhttpData()
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

    public func connected(connection: WebSocketConnection) {
        connections[connection.id] = connection
        getenvRequest()
        sendTitle()
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


    public func sendTitle()  {
        let titleLine = JSON(["topic":"title","payload":[
            "title":"Application Metrics for Swift",
            "docs": "http://github.com/RuntimeTools/SwiftMetrics"]])

         for (_,connection) in connections {
            if let messageToSend = titleLine.rawString() {
                connection.send(message: messageToSend)
            }
        }
    }

    public func storeHTTP(myhttp: HTTPData) {
        let localmyhttp = myhttp
    	  httpQueue.sync {
            if self.httpAggregateData.total == 0 {
                self.httpAggregateData.total = 1
                self.httpAggregateData.timeOfRequest = localmyhttp.timeOfRequest
                self.httpAggregateData.url = localmyhttp.url
                self.httpAggregateData.longest = localmyhttp.duration
                self.httpAggregateData.average = localmyhttp.duration
            } else {
                let oldTotalAsDouble:Double = Double(self.httpAggregateData.total)
                let newTotal = self.httpAggregateData.total + 1
                self.httpAggregateData.total = newTotal
                self.httpAggregateData.average = (self.httpAggregateData.average * oldTotalAsDouble + localmyhttp.duration) / Double(newTotal)
                if (localmyhttp.duration > self.httpAggregateData.longest) {
                    self.httpAggregateData.longest = localmyhttp.duration
                    self.httpAggregateData.url = localmyhttp.url
                }
            }
        }
        httpURLsQueue.async {
            let urlTuple = self.httpURLData[localmyhttp.url]
            if(urlTuple != nil) {
                let averageResponseTime = urlTuple!.0
                let hits = urlTuple!.1
                // Recalculate the average
                self.httpURLData.updateValue(((averageResponseTime * hits + localmyhttp.duration)/(hits + 1), hits + 1), forKey: localmyhttp.url)
            } else {
                self.httpURLData.updateValue((localmyhttp.duration, 1), forKey: localmyhttp.url)
            }
        }
    }

    func sendhttpData()  {
        httpQueue.sync {
            let localCopy = self.httpAggregateData
            if localCopy.total > 0 {
                let httpLine = JSON([
                "topic":"http","payload":[
                    "time":"\(localCopy.timeOfRequest)",
                    "url":"\(localCopy.url)",
                    "longest":"\(localCopy.longest)",
                    "average":"\(localCopy.average)",
                    "total":"\(localCopy.total)"]])

                for (_,connection) in self.connections {
                    if let messageToSend = httpLine.rawString() {
                        connection.send(message: messageToSend)
                    }
                }
                self.httpAggregateData = HTTPAggregateData()
            }
        }
        httpURLsQueue.sync {
            var responseData:[JSON] = []
            let localCopy = self.httpURLData
            for (key, value) in localCopy {
                let json = JSON(["url":key, "averageResponseTime": value.0])
                    responseData.append(json)
            }
            var messageToSend:String=""

            // build up the messageToSend string
            for response in responseData {
                messageToSend += response.rawString()! + ","
            }

            if !messageToSend.isEmpty {
              // remove the last ','
              messageToSend = messageToSend.substring(to: messageToSend.index(before: messageToSend.endIndex))
              // construct the final JSON obkect
              let messageToSend2 = "{\"topic\":\"httpURLs\",\"payload\":[" + messageToSend + "]}"
              for (_,connection) in self.connections {
                  connection.send(message: messageToSend2)
              }
            }
            jobsQueue.async {
                // re-run this function after 2 seconds
                sleep(2)
                self.sendhttpData()
            }
        }
    }

}
