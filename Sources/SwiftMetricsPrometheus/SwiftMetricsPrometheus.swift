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
import SwiftMetrics
import KituraNet
import Foundation
import Configuration

public class HTTPDurationSummaryHandler {
    let handler: String
    var durations: [Double] = []
    var totalDuration: Double

    public init(handler: String, durationMicros: Double) {
        self.handler = handler
        self.totalDuration = 0
        addEvent(durationMicros: durationMicros)
    }

    func addEvent(durationMicros: Double) {
        durations.append(durationMicros)
        totalDuration += durationMicros
    }

    // Returns a dictionary mapping requested quantiles to values.
    public func calculateQuantiles(quantiles: [Double]) -> [Double: Double] {
        // Sort the list first!
        durations.sort()

        // Calculate each quantile.
        var quantileMap: [Double: Double] = [:]
        quantiles.forEach( {(q: Double) -> () in
            quantileMap[q] = quantile(q)
        })
        return quantileMap
    }


    // Given a value q calculate the q-Quantile value
    // from our set of durations.
    private func quantile( _ q : Double) -> Double {
        // Saves a lot of checks later on.
        // (We cannot have durations.count = 0 as we create this object
        // withthe first value.)
        if (durations.count == 1) {
            return durations[0];
        }

        let n : Double = Double(durations.count);
        if let pos = Int(exactly: (n*q)) {
            // pos is a whole number
            if (pos < 2) {
                // pos is 0 or 1.
                return durations[0]
            } else if (pos == durations.count) {
                // pos is last element, can't interpolate.
                return durations[pos - 1]
            }
            // take average of this and the next value.
            return (durations[pos - 1] + durations[pos]) / 2.0;
        } else {
            // If we don't divide perfectly take the nearest
            // value above.
            let pos : Int = Int((n * q).rounded(.up))
            return durations[pos - 1]
        }
    }
}

public class HTTPDurationSummary {

    var handlers: [String: HTTPDurationSummaryHandler] = [:]

    public init() {
    }

    public func addRequest(url: String, durationMicros: Double) {

        if let urlparser = URL(string: url) {
            let path = urlparser.path
            if let handler = handlers[path] {
                handler.addEvent(durationMicros: durationMicros)
            } else {
                handlers[path] = HTTPDurationSummaryHandler(handler: path, durationMicros: durationMicros)
            }
        }
    }

    public func writeCounts(writer:(HTTPDurationSummaryHandler)->()) {
        handlers.forEach { key, value in
            writer(value)
        }
    }
}

public class HTTPCounterHandler {
    let handler: String
    let statusCode: Int
    let requestMethod: String
    var count: Int = 0

    public init(handler: String, statusCode: Int, requestMethod: String) {
        self.handler = handler
        self.statusCode = statusCode
        self.requestMethod = requestMethod.lowercased()
    }

    func addEvent() {
        count += 1
    }
}

public class HTTPCounter {

    var handlers: [String: HTTPCounterHandler] = [:]

    public init() {
    }

    public func addRequest(url: String, statusCode: Int, requestMethod: String) {

        if let urlparser = URL(string: url) {
            let path = urlparser.path
            let key: String = "\(path) \(statusCode) \(requestMethod)"
            if let handler = handlers[key] {
                handler.addEvent()
            } else {
                handlers[key] = HTTPCounterHandler(handler: path, statusCode: statusCode, requestMethod: requestMethod)
            }
        }
    }

    public func writeCounts(writer:(HTTPCounterHandler)->()) {
        handlers.forEach { key, value in
            writer(value)
        }
    }
}

var lastCPU: CPUData!
var lastMem: MemData!

var httpCounter: HTTPCounter = HTTPCounter()
var httpDurations: HTTPDurationSummary = HTTPDurationSummary()

var router = Router()

func cpuEvent(cpu: CPUData) {
    lastCPU = cpu
}

func memEvent(mem: MemData) {
    lastMem = mem
}

func httpEvent(http: HTTPData) {
    let statusCode = http.statusCode ?? HTTPStatusCode.unknown.rawValue
    httpCounter.addRequest(url: http.url, statusCode: statusCode, requestMethod: http.requestMethod);
    httpDurations.addRequest(url: http.url, durationMicros: http.duration * 1000.0);

}

public class SwiftMetricsPrometheus {

    var monitor:SwiftMonitor
    var SM:SwiftMetrics
    var createServer: Bool = false

    let p_quantiles: [Double] = [0.5,0.9,0.99]

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

        monitor.on(cpuEvent)
        monitor.on(memEvent)
        monitor.on(httpEvent)

        // Everything initialised, start serving /metrics
        try startServer(router: router)
    }

    deinit {
        if self.createServer {
            Kitura.stop()
        }
    }

    func startServer(router: Router) throws {

        // Display the prometheus data on /metrics
        router.all("/metrics")  { _, response, _ in
            if (lastCPU != nil) {
                response
                    .send("# HELP os_cpu_used_ratio The ratio of the systems CPU that is currently used (values are 0-1)\n")
                    .send("# TYPE os_cpu_used_ratio gauge\n")
                    .send("os_cpu_used_ratio: \(lastCPU.percentUsedBySystem)\n")
                    .send("# HELP process_cpu_used_ratio The ratio of the process CPU that is currently used (values are 0-1)\n")
                    .send("# TYPE process_cpu_used_ratio gauge\n")
                    .send("process_cpu_used_ratio: \(lastCPU.percentUsedByApplication)\n")
            }
            if (lastMem != nil) {
                response
                    .send("# HELP os_resident_memory_bytes OS memory size in bytes.\n")
                    .send("# TYPE os_resident_memory_bytes gauge\n")
                    .send("os_resident_memory_bytes \(lastMem.totalRAMUsed)\n")
                    .send("# HELP process_resident_memory_bytes Resident memory size in bytes.\n")
                    .send("# TYPE process_resident_memory_bytes gauge\n")
                    .send("process_resident_memory_bytes \(lastMem.applicationRAMUsed)\n")
                    .send("# HELP process_virtual_memory_bytes Virtual memory size in bytes.\n")
                    .send("# TYPE process_virtual_memory_bytes gauge\n")
                    .send("process_virtual_memory_bytes \(lastMem.applicationAddressSpaceSize)\n")
            }
            // HTTP Counts
            response
                .send("# HELP http_requests_total Total number of HTTP requests made.\n")
                .send("# TYPE http_requests_total counter\n")

            httpCounter.writeCounts( writer: {(handler: HTTPCounterHandler)->() in
                response.send("http_requests_total{code=\"\(handler.statusCode)\", handler=\"\(handler.handler)\", method=\"\(handler.requestMethod)\"} \(handler.count)\n")
            } )
            response
                .send("# HELP http_request_duration_microseconds The HTTP request latencies in microseconds.\n")
                .send("# TYPE http_request_duration_microseconds summary\n")
            httpDurations.writeCounts( writer: {(handler: HTTPDurationSummaryHandler)->() in
                response.send("http_request_duration_microseconds_sum{handler=\"\(handler.handler)\"} \(handler.totalDuration)\n")
                response.send("http_request_duration_microseconds_count{handler=\"\(handler.handler)\"} \(handler.durations.count)\n")
                let quantiles = handler.calculateQuantiles(quantiles:self.p_quantiles)
                quantiles.forEach { p, v in
                    response.send("http_request_duration_microseconds{handler=\"\(handler.handler)\",quantile=\"\(p)\"} \(v)\n")
                }
            } )

            // Error is thrown only by response.end() not response.send()
            try response.end()
        }

        if self.createServer {
            let configMgr = ConfigurationManager().load(.environmentVariables)
            Kitura.addHTTPServer(onPort: configMgr.port, with: router)
            print("SwiftMetricsPrometheus : Starting on port \(configMgr.port)")
            Kitura.start()
        }
    }
}
