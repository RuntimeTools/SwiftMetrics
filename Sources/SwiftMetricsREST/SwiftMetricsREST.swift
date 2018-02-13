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
      let startTime: UInt
      var endTime: UInt = 0
      var duration: UInt = 0
      var cpu: CPUSummary = CPUSummary()
      var memory: MemSummary = MemSummary()
      var httpUrls: [HttpUrlReport] = []

      init(id: String, startTime: UInt) {
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
        guard var temp_collection = smrCollectionList[i] else {
          continue;
        }
        if let index = instance.collection.httpUrls.index(where: { $0.url == http.url })  {
          temp_collection.collection.httpUrls[index].hits += 1
          if (http.duration > instance.collection.httpUrls[index].longestResponseTime ) {
            temp_collection.collection.httpUrls[index].longestResponseTime = http.duration
          }
          temp_collection.collection.httpUrls[index].averageResponseTime = ((instance.collection.httpUrls[index].averageResponseTime * Double(instance.collection.httpUrls[index].hits)) + http.duration) / Double(temp_collection.collection.httpUrls[index].hits)
        } else {
          // if index is nil, then the url wasn't found - add it
          temp_collection.collection.httpUrls.append(HttpUrlReport(url: http.url, hits: 1, averageResponseTime: http.duration, longestResponseTime: http.duration))
        }
        smrCollectionList[i] = temp_collection
      }
    }

    func startServer(router: Router) throws {
        router.route("/swiftmetrics/api/v1/collections/:id(\\d+)", mergeParameters: true)
          .get(handler: getIDdCollection)
          .put(handler: putIDdCollection)
          .delete(handler: deleteIDdCollection)

        router.route("/swiftmetrics/api/v1/collections")
          .get(handler: getCollections)
          .post(handler: postCollections)

        if self.createServer {
            let configMgr = ConfigurationManager().load(.environmentVariables)
            Kitura.addHTTPServer(onPort: configMgr.port, with: router)
            print("SwiftMetricsREST : Starting on port \(configMgr.port)")
            Kitura.start()
        }
    }

    func getCollections(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws -> Void {
      // return a list of current metrics contexts
      var collectionsList = CollectionsList()
      for (id, _) in self.smrCollectionList {
        collectionsList.collectionUris.append("\(request.originalURL)/\(id)")
      }
      let data = try! self.encoder.encode(collectionsList)
      response.send(data: data)
      // Error is thrown only by response.end() not response.send()
      try response.end()
    }

    func postCollections(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws -> Void {
      // create a new metrics collection; returns the created collection uri
      var temp_id = 0
      while (self.smrCollectionList[temp_id] != nil) {
        temp_id += 1
      }
      let idString = String(temp_id)
      let new_collection = SMRCollection(id: idString, startTime: UInt(Date().timeIntervalSince1970 * 1000))
      self.smrCollectionList[temp_id] = SMRCollectionInstance(collection: new_collection)
      response.status(HTTPStatusCode.created)
      let uriString = request.originalURL + "/" + idString
      response.headers.append("Location", value: uriString)
      let data = try! self.encoder.encode(CollectionUri(uri: uriString))
      response.send(data: data)
      // Error is thrown only by response.end() not response.send()
      try response.end()
    }

    func deleteIDdCollection(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws -> Void {
      guard let idString = request.parameters["id"], let id = Int(idString) else {
        _ = response.send(status: HTTPStatusCode.badRequest)
        try response.end()
        return
      }
      if (self.smrCollectionList[id] == nil) {
        _ = response.send(status: HTTPStatusCode.notFound)
      } else {
        self.smrCollectionList[id] = nil
        _ = response.send(status: HTTPStatusCode.noContent)
      }
      try response.end()
    }

    func putIDdCollection(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws -> Void {
      guard let idString = request.parameters["id"], let id = Int(idString) else {
        _ = response.send(status: HTTPStatusCode.badRequest)
        try response.end()
        return
      }
      if (self.smrCollectionList[id] == nil) {
        _ = response.send(status: HTTPStatusCode.notFound)
      } else {
        let new_collection = SMRCollection(id: idString, startTime: UInt(Date().timeIntervalSince1970 * 1000))
        self.smrCollectionList[id] = SMRCollectionInstance(collection: new_collection)
        _ = response.send(status: HTTPStatusCode.OK)
      }
      // Error is thrown only by response.end() not response.send()
      try response.end()
    }

    func getIDdCollection(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws -> Void {
      guard let idString = request.parameters["id"],  let id = Int(idString), var temp_collection = self.smrCollectionList[id] else {
        _ = response.send(status: HTTPStatusCode.badRequest)
        try response.end()
        return
      }
      temp_collection.collection.endTime = UInt(Date().timeIntervalSince1970 * 1000)
      temp_collection.collection.duration = temp_collection.collection.endTime - temp_collection.collection.startTime
      self.smrCollectionList[id] = temp_collection
      let data = try! self.encoder.encode(temp_collection.collection)
      response.send(data: data)
      // Error is thrown only by response.end() not response.send()
      try response.end()
    }
}
