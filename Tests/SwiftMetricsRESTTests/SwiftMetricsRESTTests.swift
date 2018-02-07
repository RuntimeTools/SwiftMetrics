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

import XCTest
import SwiftMetrics
import Configuration
import Foundation
@testable import SwiftMetricsREST

class SwiftMetricsRESTTests: XCTestCase {

    let collectionsSubpath = "/swiftmetrics/api/v1/collections"
    let decoder = JSONDecoder()

    var sm: SwiftMetrics?
    var smr: SwiftMetricsREST?
    var collectionsEndpoint: String = ""


    override func setUp() {
        super.setUp()

        do {
            sm = try SwiftMetrics()
            smr = try SwiftMetricsREST(swiftMetricsInstance: sm!)
            let configMgr = ConfigurationManager().load(.environmentVariables)
            collectionsEndpoint = "http://localhost:" + String(describing: configMgr.port) + collectionsSubpath
        } catch {
            XCTFail("Unable to instantiate SwiftMetrics")
        }
    }

    override func tearDown() {
        super.tearDown()
        sm!.stop()
        smr = nil
        sm = nil
    }

    func testSMRNoCollections() {
        let expectNoCollections = expectation(description: "Expect an empty collectionUris array")

        guard let url = URL(string: collectionsEndpoint) else {
          XCTFail("Error: cannot create URL for \(collectionsEndpoint)")
          return
        }
        let urlRequest = URLRequest(url: url)
        let session = URLSession(configuration: URLSessionConfiguration.default)
        let task = session.dataTask(with: urlRequest) { data , response, error in
          guard error == nil else {
            XCTFail("error calling GET on \(self.collectionsEndpoint)")
            print(error!)
            return
          }
          guard let responseData = data else {
            XCTFail("Error: did not receive data")
            return
          }
          do {
            let result = try self.decoder.decode(CollectionsList.self, from: responseData)
            XCTAssertTrue(result.collectionUris.isEmpty, "There should be no collections definied")
            expectNoCollections.fulfill()
            print("\(result)")
          } catch  {
            XCTFail("error trying to decode responseData into Swift struct")
            return
          }
        }
        task.resume()

        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error)
        }
    }

    func testSMRCollectionCreationAndDeletion() {
        let expectOneCollection = expectation(description: "Expect a single element in collectionUris array")
        let expectCorrectCollectionURI = expectation(description: "Expect the correct URI when creating a collection")
        let expectCorrectDeletionRepsonse = expectation(description: "Expect a 200 OK when deleting a collection")
        let expectNoCollections = expectation(description: "Expect an empty collectionUris array after deletion")

        guard let url = URL(string: collectionsEndpoint) else {
          XCTFail("Error: cannot create URL for \(collectionsEndpoint)")
          return
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        let session = URLSession(configuration: URLSessionConfiguration.default)
        let task = session.dataTask(with: urlRequest) { data , response, error in
          guard error == nil else {
            XCTFail("error calling POST on \(self.collectionsEndpoint)")
            print(error!)
            return
          }
          guard let responseData = data else {
            XCTFail("Error: did not receive data")
            return
          }
          do {
            let result = try self.decoder.decode(CollectionUri.self, from: responseData)
            XCTAssertEqual(result.uri, self.collectionsEndpoint + "/0", "URI should equal \(self.collectionsEndpoint)/0")
            expectCorrectCollectionURI.fulfill()
            print("\(result)")
            urlRequest.httpMethod = "GET"
            let task2 = session.dataTask(with: urlRequest) { data , response, error in
              guard error == nil else {
                XCTFail("error calling GET on \(self.collectionsEndpoint)")
                print(error!)
                return
              }
              guard let responseData = data else {
                XCTFail("Error: did not receive data")
                return
              }
              do {
                let result = try self.decoder.decode(CollectionsList.self, from: responseData)
                XCTAssertEqual(1, result.collectionUris.count, "There should only be one collection")
                XCTAssertEqual(result.collectionUris[0], self.collectionsEndpoint + "/0", "URI should equal \(self.collectionsEndpoint)/0")
                expectOneCollection.fulfill()
                print("\(result)")
                guard let url2 = URL(string: self.collectionsEndpoint + "/0") else {
                  XCTFail("Error: cannot create URL for \(self.collectionsEndpoint)/0")
                  return
                }
                var colletionRequest = URLRequest(url: url2)
                colletionRequest.httpMethod = "DELETE"
                let task3 = session.dataTask(with: colletionRequest) { data , response, error in
                  guard error == nil else {
                    XCTFail("error calling DELETE on \(self.collectionsEndpoint)/0")
                    print(error!)
                    return
                  }
                  guard let httpResponse = response as? HTTPURLResponse else {
                    XCTFail("Error: unable to retrieve HTTP Status code")
                    return
                  }
                  XCTAssertEqual(200, httpResponse.statusCode)
                  expectCorrectDeletionRepsonse.fulfill()
                  let task4 = session.dataTask(with: urlRequest) { data , response, error in
                    guard error == nil else {
                      XCTFail("error calling GET on \(self.collectionsEndpoint)")
                      print(error!)
                      return
                    }
                    guard let responseData = data else {
                      XCTFail("Error: did not receive data")
                      return
                    }
                    do {
                      let result = try self.decoder.decode(CollectionsList.self, from: responseData)
                      XCTAssertTrue(result.collectionUris.isEmpty, "There should be no collections definied")
                      expectNoCollections.fulfill()
                      print("\(result)")
                    } catch  {
                      XCTFail("error trying to decode responseData into Swift struct")
                      return
                    }
                  }
                  task4.resume()
                }
                task3.resume()
              } catch  {
                XCTFail("error trying to decode responseData into Swift struct")
                return
              }
            }
            task2.resume()
          } catch  {
            XCTFail("error trying to decode responseData into Swift struct")
            return
          }
        }
        task.resume()

        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error)
        }
    }

    func testSMRCollectionContents() {
        let expectCorrectID = expectation(description: "Expect the id of the collection to be correct")
        let expectCorrectTimeData = expectation(description: "Expect the collection Timings to be accurate")
        let expectCorrectCPUData = expectation(description: "Expect the collection CPU data to be within parameters")
        let expectCorrectMemoryData = expectation(description: "Expect the collection Memory data to be within parameters")
        let expectCorrectHTTPData = expectation(description: "Expect the collection HTTP data to be accurate")

        guard let url = URL(string: collectionsEndpoint) else {
          XCTFail("Error: cannot create URL for \(collectionsEndpoint)")
          return
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        let session = URLSession(configuration: URLSessionConfiguration.default)
        let task = session.dataTask(with: urlRequest) { data , response, error in
          guard error == nil else {
            XCTFail("error calling POST on \(self.collectionsEndpoint)")
            print(error!)
            return
          }
          guard let responseData = data else {
            XCTFail("Error: did not receive data")
            return
          }
          do {
            let result = try self.decoder.decode(CollectionUri.self, from: responseData)
            XCTAssertEqual(result.uri, self.collectionsEndpoint + "/0", "URI should equal \(self.collectionsEndpoint)/0")
            print("\(result)")
            // sleep for hopefully 2 CPU and 2 Memory events
            sleep(7)
            guard let url2 = URL(string: self.collectionsEndpoint + "/0") else {
              XCTFail("Error: cannot create URL for \(self.collectionsEndpoint)/0")
              return
            }
            urlRequest = URLRequest(url: url2)
            urlRequest.httpMethod = "GET"
            let task2 = session.dataTask(with: urlRequest) { data , response, error in
              let currentTime = Date().timeIntervalSince1970 * 1000
              //give 8 seconds leeway for the sleep
              let minTime = currentTime - 8000
              guard error == nil else {
                XCTFail("error calling GET on \(self.collectionsEndpoint)/0")
                print(error!)
                return
              }
              guard let responseData = data else {
                XCTFail("Error: did not receive data")
                return
              }
              do {
                let result = try self.decoder.decode(SMRCollection.self, from: responseData)
                XCTAssertEqual("0", result.id, "Collection ID should be 0")
                expectCorrectID.fulfill()
                XCTAssertLessThan(result.startTime, currentTime, "Collection was created in the future")
                XCTAssertGreaterThanOrEqual(result.startTime, minTime, "Collection created too long ago")
                XCTAssertLessThanOrEqual(result.endTime, currentTime, "Collection finished in the future")
                XCTAssertGreaterThan(result.endTime, minTime, "Collection finished too long ago")
                XCTAssertGreaterThanOrEqual(result.endTime, result.startTime, "Collection started after it finished")
                XCTAssertEqual(Int(result.endTime - result.startTime), Int(result.duration), "Duration length inaccurate")
                expectCorrectTimeData.fulfill()
                // cpu values should be between 0 and 1
                XCTAssertGreaterThanOrEqual(result.cpu.systemMean, 0, "CPU System Mean not big enough")
                XCTAssertGreaterThanOrEqual(result.cpu.processMean, 0, "CPU Process Mean not big enough")
                XCTAssertGreaterThanOrEqual(result.cpu.systemPeak, 0, "CPU System Peak not big enough")
                XCTAssertGreaterThanOrEqual(result.cpu.processPeak, 0, "CPU Process Peak not big enough")
                XCTAssertLessThanOrEqual(result.cpu.systemMean, 1, "CPU System Mean not small enough")
                XCTAssertLessThanOrEqual(result.cpu.processMean, 1, "CPU Process Mean not small enough")
                XCTAssertLessThanOrEqual(result.cpu.systemPeak, 1, "CPU System Peak not small enough")
                XCTAssertLessThanOrEqual(result.cpu.processPeak, 1, "CPU Process Peak not small enough")
                // peaks should be bigger than means
                XCTAssertGreaterThanOrEqual(result.cpu.systemPeak, result.cpu.systemMean, "CPU System Peak less than mean")
                XCTAssertGreaterThanOrEqual(result.cpu.processPeak, result.cpu.processMean, "CPU Process Peak less than mean")
                // system should be higher than process
                XCTAssertGreaterThanOrEqual(result.cpu.systemPeak, result.cpu.processPeak, "CPU Process Peak higher than System Peak")
                XCTAssertGreaterThanOrEqual(result.cpu.systemMean, result.cpu.processMean, "CPU Process Mean higher than System Mean")
                expectCorrectCPUData.fulfill()
                // mem values should be positive
                XCTAssertGreaterThanOrEqual(result.memory.systemMean, 0, "Memory System Mean not big enough")
                XCTAssertGreaterThanOrEqual(result.memory.processMean, 0, "Memory Process Mean not big enough")
                XCTAssertGreaterThanOrEqual(result.memory.systemPeak, 0, "Memory System Peak not big enough")
                XCTAssertGreaterThanOrEqual(result.memory.processPeak, 0, "Memory Process Peak not big enough")
                // peaks should be bigger than means
                XCTAssertGreaterThanOrEqual(result.memory.systemPeak, result.memory.systemMean, "Memory System Peak less than mean")
                XCTAssertGreaterThanOrEqual(result.memory.processPeak, result.memory.processMean, "Memory Process Peak less than mean")
                // system should be higher than process
                XCTAssertGreaterThanOrEqual(result.memory.systemPeak, result.memory.processPeak, "Memory Process Peak higher than System Peak")
                XCTAssertGreaterThanOrEqual(result.memory.systemMean, result.memory.processMean, "Memory Process Mean higher than System Mean")
                expectCorrectMemoryData.fulfill()
                // There should only be one HTTP record - for the creation POST call.
                XCTAssertEqual(1, result.httpUrls.count, "Only expected one HTTP record")
                XCTAssertEqual(1, result.httpUrls[0].hits, "Only expected one HTTP hit")
                XCTAssertEqual(self.collectionsEndpoint, result.httpUrls[0].url, "HTTP URL not \(self.collectionsEndpoint)/0")
                // HTTP times should be positive
                XCTAssertGreaterThanOrEqual(result.httpUrls[0].averageResponseTime, 0, "HTTP Average response time not big enough")
                XCTAssertGreaterThanOrEqual(result.httpUrls[0].longestResponseTime, 0, "HTTP Longest response time not big enough")
                // Longest should be higher than average
                XCTAssertGreaterThanOrEqual(result.httpUrls[0].longestResponseTime, result.httpUrls[0].averageResponseTime, "Memory Process Peak less than mean")
                expectCorrectHTTPData.fulfill()
                print("\(result)")
                // cleanup
                urlRequest.httpMethod = "DELETE"
                let task3 = session.dataTask(with: urlRequest) { _ , _, _ in }
                task3.resume()
              } catch  {
                XCTFail("error trying to decode responseData into Swift struct")
                return
              }
            }
            task2.resume()
          } catch  {
            XCTFail("error trying to decode responseData into Swift struct")
            return
          }
        }
        task.resume()

        waitForExpectations(timeout: 20) { error in
            XCTAssertNil(error)
        }
    }

    static var allTests : [(String, (SwiftMetricsRESTTests) -> () throws -> Void)] {
        return [
          ("SMRNoCollections", testSMRNoCollections),
          ("SMRCollectionCreationAndDeletion", testSMRCollectionCreationAndDeletion),
          ("SMRCollectionContents", testSMRCollectionContents),
        ]
    }
}
