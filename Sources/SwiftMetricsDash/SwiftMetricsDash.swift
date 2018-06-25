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
import CloudFoundryEnv
import Dispatch

struct HTTPAggregateData: SMData {
    public var timeOfRequest: Int = 0
    public var url: String = ""
    public var longest: Double = 0
    public var average: Double = 0
    public var total: Int = 0
}

// Structs for CPU Data and wrapper object
struct CpuData: Codable {
    let process: Float
    let systemMean: Double
    let processMean: Double
    let time: Int
    let system: Float
}

struct Cpu: Codable {
    let topic = "cpu"
    let payload: CpuData
}

struct MemoryData: Codable {
    let time: Int
    let physical: Int
    let physical_used: Int
    let processMean: Int
    let systemMean: Int
}

struct Memory: Codable {
    let topic = "memory"
    let payload: MemoryData
}

struct TitleData: Codable {
    let title: String
    let docs: String
}

struct Title: Codable {
    let topic = "title"
    let payload: TitleData
}

struct HTTPRequestsData: Codable {
    let time: Int
    let url: String
    let longest: Double
    let average: Double
    let total: Int
}

struct HTTPRequests: Codable {
    let topic = "http"
    let payload: HTTPRequestsData
}

struct HTTPResponseData: Codable {
    let url: String
    let averageResponseTime: Double
    let hits: Double
    let longestResponseTime: Double
}

struct Env: Codable {
    let topic = "env"
    let payload: [EnvParams]
}

struct EnvParams: Codable {
    let Parameter: String
    let Value: String
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
    var httpURLData:[String:(totalTime:Double, numHits:Double, longestTime:Double)] = [:]
    let httpURLsQueue = DispatchQueue(label: "httpURLsQueue")
    let httpQueue = DispatchQueue(label: "httpStoreQueue")
    let jobsQueue = DispatchQueue(label: "jobsQueue")
    var monitor:SwiftMonitor
    let encoder = JSONEncoder()

    // CPU summary data
    var totalProcessCPULoad: Double = 0.0;
    var totalSystemCPULoad: Double = 0.0;
    var cpuLoadSamples: Double = 0

    // Memory summary data
    var totalProcessMemory: Int = 0;
    var totalSystemMemory: Int = 0;
    var memorySamples: Int = 0;



    public init(monitor: SwiftMonitor) {
        self.monitor = monitor
        monitor.on(sendCPU)
        monitor.on(sendMEM)
        monitor.on(storeHTTP)
        sendhttpData()
    }



    func sendCPU(cpu: CPUData) {
        totalProcessCPULoad += Double(cpu.percentUsedByApplication);
        totalSystemCPULoad += Double(cpu.percentUsedBySystem);
        cpuLoadSamples += 1;
        let processMean = (totalProcessCPULoad / cpuLoadSamples);
        let systemMean = (totalSystemCPULoad / cpuLoadSamples);

        let cpu = Cpu(payload: CpuData(
            process: cpu.percentUsedByApplication,
            systemMean: systemMean,
            processMean: processMean,
            time: cpu.timeOfSample,
            system: cpu.percentUsedBySystem
        ))

        sendCodable(mData: cpu)
    }


    func sendMEM(mem: MemData) {
        totalProcessMemory += mem.applicationRAMUsed;
        totalSystemMemory += mem.totalRAMUsed;
        memorySamples += 1;
        let processMean = (totalProcessMemory / memorySamples);
        let systemMean = (totalSystemMemory / memorySamples);

        let memory = Memory(payload: MemoryData(
            time: mem.timeOfSample,
            physical: mem.applicationRAMUsed,
            physical_used: mem.totalRAMUsed,
            processMean: processMean,
            systemMean: systemMean
        ))

        sendCodable(mData: memory)
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

        let env = Env(payload: [
            EnvParams(Parameter: "Command Line", Value: commandLine),
            EnvParams(Parameter: "Hostname", Value: hostname),
            EnvParams(Parameter: "Number of Processors", Value: numPar),
            EnvParams(Parameter: "OS Architecture", Value: os)
        ])

        sendCodable(mData: env)
    }


    public func sendTitle()  {
        let title = Title(payload: TitleData(
            title: "Application Metrics for Swift",
            docs: "http://github.com/RuntimeTools/SwiftMetrics"
        ))

        sendCodable(mData: title)
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
                var longest = urlTuple!.2
                if (localmyhttp.duration > longest) {
                    longest = localmyhttp.duration
                }
                // Recalculate the average
                self.httpURLData.updateValue(((averageResponseTime * hits + localmyhttp.duration)/(hits + 1), hits + 1, longest), forKey: localmyhttp.url)
            } else {
                self.httpURLData.updateValue((localmyhttp.duration, 1, localmyhttp.duration), forKey: localmyhttp.url)
            }
        }
    }

    func sendhttpData()  {
        httpQueue.sync {
            let localCopy = self.httpAggregateData
            if localCopy.total > 0 {

                let httpData = HTTPRequests(payload: HTTPRequestsData(
                    time: localCopy.timeOfRequest,
                    url: localCopy.url,
                    longest: localCopy.longest,
                    average: localCopy.average,
                    total: localCopy.total
                ))

                sendCodable(mData: httpData)

                self.httpAggregateData = HTTPAggregateData()
            }
        }
        httpURLsQueue.sync {
            var responseData:[String] = []
            let localCopy = self.httpURLData
            for (key, value) in localCopy {
                let json = HTTPResponseData(
                    url: key,
                    averageResponseTime: value.0,
                    hits: value.1,
                    longestResponseTime: value.2
                )
                // encode memory as JSON object
                let data = try! encoder.encode(json)
                responseData.append(String(data: data, encoding: .utf8)!)
            }
            var messageToSend:String=""

            // build up the messageToSend string
            for response in responseData {
                messageToSend += response + ","
            }

            if !messageToSend.isEmpty {
                // remove the last ','
                messageToSend = String(messageToSend[..<messageToSend.index(before: messageToSend.endIndex)])
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

    func sendCodable<MESSAGE: Codable>(mData: MESSAGE) {
        // encode memory as JSON object
        let data = try! encoder.encode(mData)
        // send data in connections
        for (_,connection) in connections {
            connection.send(message: String(data: data, encoding: .utf8)!)
        }
    }

}
