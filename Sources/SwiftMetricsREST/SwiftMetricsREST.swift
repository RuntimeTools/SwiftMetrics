/**
 * Copyright IBM Corporation 2018
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

    public struct CPUSummary: Codable {
      var systemMean: Double = 0.0
      var systemPeak: Double = 0.0
      var processMean: Double = 0.0
      var processPeak: Double = 0.0
    }

    public struct MemSummary: Codable {
      var systemMean: UInt = 0
      var systemPeak: UInt = 0
      var processMean: UInt = 0
      var processPeak: UInt = 0
    }

    public struct HttpUrlReport: Codable {
      let url: String
      var hits: Int = 0
      var averageResponseTime: Double = 0.0
      var longestResponseTime: Double = 0.0
    }

    public struct SMRCollection: Codable {
      let id: String
      let startTime: Double
      var endTime: Double = 0
      var duration: Double = 0
      var cpu: CPUSummary = CPUSummary()
      var memory: MemSummary = MemSummary()
      var httpUrls: [HttpUrlReport] = []

      init(id: String, startTime: Double) {
        self.id = id
        self.startTime = startTime
      }
    }

    public struct SMRCollectionInstance: Codable {
      var collection: SMRCollection
      var cpuSampleCount: Int = 0
      var memSampleCount: Int = 0

      init(collection: SMRCollection) {
        self.collection = collection
      }
    }

    public struct CollectionsList: Codable {
      var collectionUris: [String] = []
    }

    public struct CollectionUri: Codable {
      var uri: String
    }

public class SwiftMetricsREST {

    var router = Router()
    var monitor: SwiftMonitor
    var SM: SwiftMetrics
    var createServer: Bool = false
    var smrCollectionList: [Int: SMRCollectionInstance] = [:]


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

    private func cpuEvent(cpu: CPUData) {
        let procCPU = Double(cpu.percentUsedByApplication)
        let sysCPU = Double(cpu.percentUsedBySystem)
        for (index, instance) in smrCollectionList {
          guard var temp_collection = smrCollectionList[index] else {
            continue;
          }
          temp_collection.cpuSampleCount += 1
          if (procCPU > instance.collection.cpu.processPeak) {
            temp_collection.collection.cpu.processPeak = procCPU
          }
          temp_collection.collection.cpu.processMean = ((instance.collection.cpu.processMean * Double(instance.cpuSampleCount)) + procCPU) / Double(temp_collection.cpuSampleCount)
          if (sysCPU > instance.collection.cpu.systemPeak) {
            temp_collection.collection.cpu.systemPeak = sysCPU
          }
          temp_collection.collection.cpu.systemMean = ((instance.collection.cpu.systemMean * Double(instance.cpuSampleCount)) + sysCPU) / Double(temp_collection.cpuSampleCount)
          smrCollectionList[index] = temp_collection
        }
    }

    private func memEvent(mem: MemData) {
      for (index, instance) in smrCollectionList {
        guard var temp_collection = smrCollectionList[index] else {
          continue;
        }
        temp_collection.memSampleCount += 1
        if (mem.applicationRAMUsed > instance.collection.memory.processPeak) {
          temp_collection.collection.memory.processPeak = UInt(mem.applicationRAMUsed)
        }
        temp_collection.collection.memory.processMean = ((instance.collection.memory.processMean * UInt(instance.memSampleCount)) + UInt(mem.applicationRAMUsed)) / UInt(temp_collection.memSampleCount)
        if (mem.totalRAMUsed > instance.collection.memory.systemPeak) {
          temp_collection.collection.memory.systemPeak = UInt(mem.totalRAMUsed)
        }
        temp_collection.collection.memory.systemMean = ((instance.collection.memory.systemMean * UInt(instance.memSampleCount)) + UInt(mem.totalRAMUsed)) / UInt(temp_collection.memSampleCount)
        smrCollectionList[index] = temp_collection
      }
    }

    private func httpEvent(http: HTTPData) {
      for (i, instance) in smrCollectionList {
        var notFound = true
        guard var temp_collection = smrCollectionList[i] else {
          continue;
        }
        for (index, httpReport) in instance.collection.httpUrls.enumerated() {
          if (http.url == httpReport.url ) {
            temp_collection.collection.httpUrls[index].hits += 1
            if (http.duration > httpReport.longestResponseTime) {
              temp_collection.collection.httpUrls[index].longestResponseTime = http.duration
            }
            temp_collection.collection.httpUrls[index].averageResponseTime = ((httpReport.averageResponseTime * Double(httpReport.hits)) + http.duration) / Double(temp_collection.collection.httpUrls[index].hits)
            notFound = false
            break
          }
        }
        if (notFound) {
          temp_collection.collection.httpUrls.append(HttpUrlReport(url: http.url, hits: 1, averageResponseTime: http.duration, longestResponseTime: http.duration))
        }
        smrCollectionList[i] = temp_collection
      }
    }

    func startServer(router: Router) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        router.route("/swiftmetrics/api/v1/collections/:id(\\d+)", mergeParameters: true)
          .get() { req, response, _ in
            guard let idString = req.parameters["id"],  let id = Int(idString), var temp_collection = self.smrCollectionList[id] else {
              _ = response.send(status: HTTPStatusCode.badRequest)
              try response.end()
              return
            }
            temp_collection.collection.endTime = Date().timeIntervalSince1970 * 1000
            temp_collection.collection.duration = temp_collection.collection.endTime - temp_collection.collection.startTime
            self.smrCollectionList[id] = temp_collection
            let data = try! encoder.encode(temp_collection.collection)
            response.send(data: data)
            // Error is thrown only by response.end() not response.send()
            try response.end()
          }
          .put() { req, response, _ in
            guard let idString = req.parameters["id"], let id = Int(idString), var temp_collection = self.smrCollectionList[id] else {
              _ = response.send(status: HTTPStatusCode.badRequest)
              try response.end()
              return
            }
            // set duration
            temp_collection.collection.endTime = Date().timeIntervalSince1970 * 1000
            temp_collection.collection.duration = temp_collection.collection.endTime - temp_collection.collection.startTime
            let data = try! encoder.encode(temp_collection.collection)
            response.send(data: data)
            let new_collection = SMRCollection(id: idString, startTime: Date().timeIntervalSince1970 * 1000)
            self.smrCollectionList[id] = SMRCollectionInstance(collection: new_collection)
            // Error is thrown only by response.end() not response.send()
            try response.end()
          }
          .delete() { req, response, _ in
            guard let idString = req.parameters["id"], let id = Int(idString) else {
              _ = response.send(status: HTTPStatusCode.badRequest)
              try response.end()
              return
            }
            self.smrCollectionList[id] = nil
            _ = response.send(status: HTTPStatusCode.OK)
            try response.end()
          }

        router.route("/swiftmetrics/api/v1/collections")
          .get()  { request, response, _ in
            // return a list of current metrics contexts
            var collectionsList = CollectionsList()
            for (id, _) in self.smrCollectionList {
              collectionsList.collectionUris.append("\(request.originalURL)/\(id)")
            }
            let data = try! encoder.encode(collectionsList)
            response.send(data: data)
            // Error is thrown only by response.end() not response.send()
            try response.end()
          }
          .post() { request, response, _ in
            // create a new metrics collection; returns the created collection uri
            var temp_id = 0
            while (self.smrCollectionList[temp_id] != nil) {
              temp_id += 1
            }
            let new_collection = SMRCollection(id: String(temp_id), startTime: Date().timeIntervalSince1970 * 1000)
            self.smrCollectionList[temp_id] = SMRCollectionInstance(collection: new_collection)
            let data = try! encoder.encode(CollectionUri(uri: "\(request.originalURL)/\(temp_id)"))
            response.send(data: data)
            // Error is thrown only by response.end() not response.send()
            try response.end()
          }

        if self.createServer {
            let configMgr = ConfigurationManager().load(.environmentVariables)
            Kitura.addHTTPServer(onPort: configMgr.port, with: router)
            print("SwiftMetricsREST : Starting on port \(configMgr.port)")
            Kitura.start()
        }
    }
}
