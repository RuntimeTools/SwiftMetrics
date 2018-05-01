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
      let id: Int
      let startTime: UInt
      var endTime: UInt
      var duration: UInt = 0
      var cpu: CPUSummary = CPUSummary()
      var memory: MemSummary = MemSummary()
      var httpUrls: [HttpUrlReport] = []

      init(id: Int, startTime: UInt) {
        self.id = id
        self.startTime = startTime
        self.endTime = startTime
      }
    }

    public struct SMRCollectionInstance: Codable {
      var collection: SMRCollection
      var cpuSampleCount: Double = 0.0
      var memSampleCount: UInt = 0

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
    var createServer: Bool = false
    var smrCollectionList: [Int: SMRCollectionInstance] = [:]
    let encoder = JSONEncoder()

    public convenience init(swiftMetricsInstance : SwiftMetrics) throws {
        try self.init(swiftMetricsInstance : swiftMetricsInstance , endpoint: nil)
    }

    public init(swiftMetricsInstance : SwiftMetrics , endpoint: Router!) throws {
        encoder.outputFormatting = .prettyPrinted

        let SM = swiftMetricsInstance
        _ = SwiftMetricsKitura(swiftMetricsInstance: SM)
        let monitor = SM.monitor()

        monitor.on(httpEvent)
        monitor.on(cpuEvent)
        monitor.on(memEvent)

        // default to use passed in Router
        if endpoint == nil {
            self.createServer = true
        } else {
            router =  endpoint
        }

        // Everything initialised, start serving metrics
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
        for key in smrCollectionList.keys {
          guard var temp_cpuSummary = smrCollectionList[key]?.collection.cpu, let count = smrCollectionList[key]?.cpuSampleCount else {
            continue;
          }
          smrCollectionList[key]!.cpuSampleCount += 1.0
          if (procCPU > temp_cpuSummary.processPeak) {
            temp_cpuSummary.processPeak = procCPU
          }
          temp_cpuSummary.processMean = ((temp_cpuSummary.processMean * count) + procCPU) / smrCollectionList[key]!.cpuSampleCount
          if (sysCPU > temp_cpuSummary.systemPeak) {
            temp_cpuSummary.systemPeak = sysCPU
          }
          temp_cpuSummary.systemMean = ((temp_cpuSummary.systemMean * count) + sysCPU) / smrCollectionList[key]!.cpuSampleCount
          smrCollectionList[key]!.collection.cpu = temp_cpuSummary
        }
    }

    private func memEvent(mem: MemData) {
      for key in smrCollectionList.keys {
        let procMem = UInt(mem.applicationRAMUsed)
        let sysMem = UInt(mem.totalRAMUsed)
        guard var temp_memSummary = smrCollectionList[key]?.collection.memory, let count = smrCollectionList[key]?.memSampleCount else {
          continue;
        }
        smrCollectionList[key]!.memSampleCount += 1
        if (procMem > temp_memSummary.processPeak) {
          temp_memSummary.processPeak = procMem
        }
        temp_memSummary.processMean = ((temp_memSummary.processMean * count) + procMem) / smrCollectionList[key]!.memSampleCount
        if (sysMem > temp_memSummary.systemPeak) {
          temp_memSummary.systemPeak = sysMem
        }
        temp_memSummary.systemMean = ((temp_memSummary.systemMean * count) + sysMem) / smrCollectionList[key]!.memSampleCount
        smrCollectionList[key]!.collection.memory = temp_memSummary
      }
    }

    private func httpEvent(http: HTTPData) {
      for key in smrCollectionList.keys {
        guard var temp_httpUrlReports = smrCollectionList[key]?.collection.httpUrls else {
          continue;
        }
        if let index = temp_httpUrlReports.index(where: { $0.url == http.url })  {
          temp_httpUrlReports[index].hits += 1
          if (http.duration > temp_httpUrlReports[index].longestResponseTime ) {
            temp_httpUrlReports[index].longestResponseTime = http.duration
          }
          temp_httpUrlReports[index].averageResponseTime = ((temp_httpUrlReports[index].averageResponseTime * Double(temp_httpUrlReports[index].hits - 1)) + http.duration) / Double(temp_httpUrlReports[index].hits)
        } else {
          // if index is nil, then the url wasn't found - add it
          temp_httpUrlReports.append(HttpUrlReport(url: http.url, hits: 1, averageResponseTime: http.duration, longestResponseTime: http.duration))
        }
        smrCollectionList[key]!.collection.httpUrls = temp_httpUrlReports
      }
    }

    func startServer(router: Router) throws {
        router.route("/swiftmetrics/api/v1/collections/:id(\\d+)", mergeParameters: true)
          .all(handler: checkIDdCollection)

        router.route("/swiftmetrics/api/v1/collections")
          .get(handler: getCollections)
          .post(handler: postCollections)

        if self.createServer {
            let configMgrPort = ConfigurationManager().load(.environmentVariables).port
            Kitura.addHTTPServer(onPort: configMgrPort, with: router)
            print("SwiftMetricsREST : Starting on port \(configMgrPort)")
            Kitura.start()
        }
    }

    func getCollections(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws -> Void {
      // return a list of current metrics contexts
      var collectionsList = CollectionsList()
      for id in self.smrCollectionList.keys.sorted() {
        collectionsList.collectionUris.append("collections/\(id)")
      }
      // Error is thrown only by response.end() not response.send()
      try response.status(HTTPStatusCode.OK).send(data: try! self.encoder.encode(collectionsList)).end()
    }

    func postCollections(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws -> Void {
      // create a new metrics collection; returns the created collection uri
      var new_id = 0
      while (self.smrCollectionList[new_id] != nil) {
        new_id += 1
      }
      self.smrCollectionList[new_id] = SMRCollectionInstance(collection: SMRCollection(id: new_id, startTime: UInt(Date().timeIntervalSince1970 * 1000)))
      let uriString = "vollections/" + String(new_id)
      response.headers.append("Location", value: uriString)
      // Error is thrown only by response.end() not response.send()
      try response.status(HTTPStatusCode.created).send(data: try! self.encoder.encode(CollectionUri(uri: uriString))).end()
    }

    func checkIDdCollection(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws -> Void {
      if let idString = request.parameters["id"], let id = Int(idString) {
        if (self.smrCollectionList[id] == nil) {
          // Error is thrown only by response.end() not response.send()
          try response.send(status: HTTPStatusCode.notFound).end()
        } else {
          try processIDdCollection(requestMethod: request.method, response: response, id: id)
        }
      } else {
        // Error is thrown only by response.end() not response.send()
        try response.send(status: HTTPStatusCode.badRequest).end()
      }
    }

    func processIDdCollection(requestMethod: RouterMethod, response: RouterResponse, id: Int) throws -> Void {
      switch requestMethod {
      case RouterMethod.delete:
        try deleteIDdCollection(response: response, id: id)
      case RouterMethod.put:
        try putIDdCollection(response: response, id: id)
      case RouterMethod.get:
        try getIDdCollection(response: response, id: id)
      default:
        // Error is thrown only by response.end() not response.send()
        try response.send(status: HTTPStatusCode.badRequest).end()
      }
    }

    func deleteIDdCollection(response: RouterResponse, id: Int) throws -> Void {
      self.smrCollectionList[id] = nil
      // Error is thrown only by response.end() not response.send()
      try response.send(status: HTTPStatusCode.noContent).end()
    }

    func putIDdCollection(response: RouterResponse, id: Int) throws -> Void {
      self.smrCollectionList[id] = SMRCollectionInstance(collection: SMRCollection(id: id, startTime: UInt(Date().timeIntervalSince1970 * 1000)))
      // Error is thrown only by response.end() not response.send()
      try response.send(status: HTTPStatusCode.noContent).end()
    }

    func getIDdCollection(response: RouterResponse, id: Int) throws -> Void {
      self.smrCollectionList[id]!.collection.endTime = UInt(Date().timeIntervalSince1970 * 1000)
      self.smrCollectionList[id]!.collection.duration = self.smrCollectionList[id]!.collection.endTime - self.smrCollectionList[id]!.collection.startTime
      // Error is thrown only by response.end() not response.send()
      try response.status(HTTPStatusCode.OK).send(data: try! self.encoder.encode(self.smrCollectionList[id]!.collection)).end()
    }
}
