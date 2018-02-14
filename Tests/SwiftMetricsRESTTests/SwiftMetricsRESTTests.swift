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
        let tSMRNCtask = session.dataTask(with: urlRequest) { data , response, error in
          guard error == nil else {
            XCTFail("error calling GET on \(self.collectionsEndpoint)")
            print(error!)
            return
          }
          guard let responseData = data else {
            XCTFail("Error: did not receive data")
            return
          }
          guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Error: unable to retrieve HTTP Status code")
            return
          }
          do {
            XCTAssertEqual(200, httpResponse.statusCode)
            let result = try self.decoder.decode(CollectionsList.self, from: responseData)
            XCTAssertTrue(result.collectionUris.isEmpty, "There should be no collections definied")
            expectNoCollections.fulfill()
            print("\(result)")
          } catch  {
            XCTFail("error trying to decode responseData into Swift struct")
            return
          }
        }
        tSMRNCtask.resume()

        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error)
        }
    }

    func testSMRCollectionCreationAndDeletion() {
        let expectOneCollection = expectation(description: "Expect a single element in collectionUris array")
        let expectCorrectCollectionURI = expectation(description: "Expect the correct URI when creating a collection")
        let expectCorrectDeletionRepsonse = expectation(description: "Expect a 200 OK when deleting a collection")

        guard let url = URL(string: collectionsEndpoint) else {
          XCTFail("Error: cannot create URL for \(collectionsEndpoint)")
          return
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        let session = URLSession(configuration: URLSessionConfiguration.default)
        let tSMRCCADtask = session.dataTask(with: urlRequest) { data , response, error in
          guard error == nil else {
            XCTFail("error calling POST on \(self.collectionsEndpoint)")
            print(error!)
            return
          }
          guard let responseData = data else {
            XCTFail("Error: did not receive data")
            return
          }
          guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Error: unable to retrieve HTTP Status code")
            return
          }
          do {
            XCTAssertEqual(201, httpResponse.statusCode)
            let result = try self.decoder.decode(CollectionUri.self, from: responseData)
            XCTAssertEqual(result.uri, self.collectionsEndpoint + "/0", "URI should equal \(self.collectionsEndpoint)/0")
            XCTAssertEqual(result.uri, httpResponse.allHeaderFields["Location"] as! String, "URI should be available in response header 'Location'")
            expectCorrectCollectionURI.fulfill()
            print("\(result)")
            urlRequest.httpMethod = "GET"
            let tSMRCCADtask2 = session.dataTask(with: urlRequest) { data , response, error in
              guard error == nil else {
                XCTFail("error calling GET on \(self.collectionsEndpoint)")
                print(error!)
                return
              }
              guard let responseData = data else {
                XCTFail("Error: did not receive data")
                return
              }
              guard let httpResponse = response as? HTTPURLResponse else {
                XCTFail("Error: unable to retrieve HTTP Status code")
                return
              }
              do {
                XCTAssertEqual(200, httpResponse.statusCode)
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
                let tSMRCCADtask3 = session.dataTask(with: colletionRequest) { data , response, error in
                  guard error == nil else {
                    XCTFail("error calling DELETE on \(self.collectionsEndpoint)/0")
                    print(error!)
                    return
                  }
                  guard let httpResponse = response as? HTTPURLResponse else {
                    XCTFail("Error: unable to retrieve HTTP Status code")
                    return
                  }
                  XCTAssertEqual(204, httpResponse.statusCode)
                  expectCorrectDeletionRepsonse.fulfill()
                }
                tSMRCCADtask3.resume()
              } catch  {
                XCTFail("error trying to decode responseData into Swift struct")
                return
              }
            }
            tSMRCCADtask2.resume()
          } catch  {
            XCTFail("error trying to decode responseData into Swift struct")
            return
          }
        }
        tSMRCCADtask.resume()

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
        let tSMRCCtask = session.dataTask(with: urlRequest) { data , response, error in
          guard error == nil else {
            XCTFail("error calling POST on \(self.collectionsEndpoint)")
            print(error!)
            return
          }
          guard let responseData = data else {
            XCTFail("Error: did not receive data")
            return
          }
          guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Error: unable to retrieve HTTP Status code")
            return
          }
          do {
            XCTAssertEqual(201, httpResponse.statusCode)
            let result = try self.decoder.decode(CollectionUri.self, from: responseData)
            XCTAssertEqual(result.uri, self.collectionsEndpoint + "/0", "URI should equal \(self.collectionsEndpoint)/0")
            print("\(result)")
            // sleep for hopefully 2 CPU and 2 Memory events
            sleep(20)
            guard let url2 = URL(string: self.collectionsEndpoint + "/0") else {
              XCTFail("Error: cannot create URL for \(self.collectionsEndpoint)/0")
              return
            }
            urlRequest = URLRequest(url: url2)
            urlRequest.httpMethod = "GET"
            let tSMRCCtask2 = session.dataTask(with: urlRequest) { data , response, error in
              let currentTime = UInt(Date().timeIntervalSince1970 * 1000)
              //give 16 seconds leeway for the sleep
              let minTime = currentTime - 21000
              guard error == nil else {
                XCTFail("error calling GET on \(self.collectionsEndpoint)/0")
                print(error!)
                return
              }
              guard let responseData = data else {
                XCTFail("Error: did not receive data")
                return
              }
              guard let httpResponse = response as? HTTPURLResponse else {
                XCTFail("Error: unable to retrieve HTTP Status code")
                return
              }
              do {
                XCTAssertEqual(200, httpResponse.statusCode)
                let result = try self.decoder.decode(SMRCollection.self, from: responseData)
                XCTAssertEqual("0", result.id, "Collection ID should be 0")
                expectCorrectID.fulfill()
                XCTAssertLessThan(result.startTime, currentTime, "Collection was created in the future")
                XCTAssertGreaterThanOrEqual(result.startTime, minTime, "Collection created too long ago")
                XCTAssertLessThanOrEqual(result.endTime, currentTime, "Collection finished in the future")
                XCTAssertGreaterThan(result.endTime, minTime, "Collection finished too long ago")
                XCTAssertGreaterThanOrEqual(result.endTime, result.startTime, "Collection started after it finished")
                XCTAssertEqual(result.endTime - result.startTime, result.duration, "Duration length inaccurate")
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
                let tSMRCCtask3 = session.dataTask(with: urlRequest) { _ , _, _ in }
                tSMRCCtask3.resume()
              } catch  {
                XCTFail("error trying to decode responseData into Swift struct")
                return
              }
            }
            tSMRCCtask2.resume()
          } catch  {
            XCTFail("error trying to decode responseData into Swift struct")
            return
          }
        }
        tSMRCCtask.resume()

        waitForExpectations(timeout: 30) { error in
            XCTAssertNil(error)
        }
    }

    func testSMRResetCollectionOnPut() {
        let expectCollectionReset = expectation(description: "Expect a zero'ed collection on PUT")

        guard let url = URL(string: collectionsEndpoint) else {
          XCTFail("Error: cannot create URL for \(collectionsEndpoint)")
          return
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        let session = URLSession(configuration: URLSessionConfiguration.default)
        let tSMRRCOPtask = session.dataTask(with: urlRequest) { data , response, error in
          guard error == nil else {
            XCTFail("error calling POST on \(self.collectionsEndpoint)")
            print(error!)
            return
          }
          guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Error: unable to retrieve HTTP Status code")
            return
          }
          guard let responseData = data else {
            XCTFail("Error: did not receive data")
            return
          }
          do {
            XCTAssertEqual(201, httpResponse.statusCode)
            let result = try self.decoder.decode(CollectionUri.self, from: responseData)
            let uriString = result.uri
            let splitUriString = uriString.split(separator: "/")
            let collectionID = String(splitUriString[splitUriString.count - 1])
            guard let url2 = URL(string: uriString) else {
              XCTFail("Error: cannot create URL for \(result.uri)")
              return
            }
            // wait for some time to pass before resetting
            sleep(8)
            var urlRequest2 = URLRequest(url: url2)
            urlRequest2.httpMethod = "PUT"
            let tSMRRCOPtask2 = session.dataTask(with: urlRequest2) { data , response, error in
              guard error == nil else {
                XCTFail("error calling PUT on \(uriString)")
                print(error!)
                return
              }
              guard let httpResponse = response as? HTTPURLResponse else {
                XCTFail("Error: unable to retrieve HTTP Status code")
                return
              }
              XCTAssertEqual(200, httpResponse.statusCode)
              urlRequest2.httpMethod = "GET"
              let tSMRRCOPtask3 = session.dataTask(with: urlRequest2) { data , response, error in
                guard error == nil else {
                  XCTFail("error calling GET on \(uriString)")
                  print(error!)
                  return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                  XCTFail("Error: unable to retrieve HTTP Status code")
                  return
                }
                guard let responseData = data else {
                  XCTFail("Error: did not receive data")
                  return
                }
                do {
                  let currentTime = UInt(Date().timeIntervalSince1970 * 1000)
                  // reset takes place in under a second
                  let minTime = currentTime - 1000
                  XCTAssertEqual(200, httpResponse.statusCode)
                  let result = try self.decoder.decode(SMRCollection.self, from: responseData)
                  XCTAssertEqual(collectionID, result.id, "Collection ID should be \(collectionID)")
                  XCTAssertLessThan(result.startTime, currentTime, "Collection was created in the future")
                  XCTAssertGreaterThanOrEqual(result.startTime, minTime, "Collection created too long ago")
                  XCTAssertLessThanOrEqual(result.endTime, currentTime, "Collection finished in the future")
                  XCTAssertGreaterThan(result.endTime, minTime, "Collection finished too long ago")
                  XCTAssertGreaterThanOrEqual(result.endTime, result.startTime, "Collection started after it finished")
                  XCTAssertEqual(result.endTime - result.startTime, result.duration, "Duration length inaccurate")
                  // cpu values should be 0.0
                  XCTAssertEqual(result.cpu.systemMean, 0.0, "CPU System Mean too big")
                  XCTAssertEqual(result.cpu.processMean, 0.0, "CPU Process Mean too big")
                  XCTAssertEqual(result.cpu.systemPeak, 0.0, "CPU System Peak too big")
                  XCTAssertEqual(result.cpu.processPeak, 0.0, "CPU Process Peak too big")
                  // mem values should be 0
                  XCTAssertEqual(result.memory.systemMean, 0, "Memory System Mean too big")
                  XCTAssertEqual(result.memory.processMean, 0, "Memory Process Mean too big")
                  XCTAssertEqual(result.memory.systemPeak, 0, "Memory System Peak too big")
                  XCTAssertEqual(result.memory.processPeak, 0, "Memory Process Peak too big")
                  // There should only be one HTTP record - for the PUT call.
                  XCTAssertEqual(1, result.httpUrls.count, "Only expected one HTTP record")
                  XCTAssertEqual(1, result.httpUrls[0].hits, "Only expected one HTTP hit")
                  XCTAssertEqual(uriString, result.httpUrls[0].url, "HTTP URL not \(uriString)")
                  // HTTP times should be positive
                  XCTAssertGreaterThanOrEqual(result.httpUrls[0].averageResponseTime, 0, "HTTP Average response time not big enough")
                  XCTAssertGreaterThanOrEqual(result.httpUrls[0].longestResponseTime, 0, "HTTP Longest response time not big enough")
                  // Longest should be higher than average
                  XCTAssertGreaterThanOrEqual(result.httpUrls[0].longestResponseTime, result.httpUrls[0].averageResponseTime, "Memory Process Peak less than mean")
                  expectCollectionReset.fulfill()
                  print("\(result)")
                  // cleanup
                  urlRequest2.httpMethod = "DELETE"
                  let tSMRRCOPtask4 = session.dataTask(with: urlRequest2) { _ , _, _ in }
                  tSMRRCOPtask4.resume()
                } catch {
                  XCTFail("error trying to decode responseData into SMRCollection struct")
                  return
                }
              }
              tSMRRCOPtask3.resume()
            }
            tSMRRCOPtask2.resume()
          } catch {
            XCTFail("error trying to decode responseData into CollectionUri struct")
            return
          }
        }
        tSMRRCOPtask.resume()

        waitForExpectations(timeout: 20) { error in
            XCTAssertNil(error)
        }
    }

    func testSMRFailOnGetInvalidCollection() {
        let expect404Failure = expectation(description: "Expect a 404 NOT FOUND response to GETting a non-existant collection")

        guard let url = URL(string: collectionsEndpoint + "/777") else {
          XCTFail("Error: cannot create URL for \(collectionsEndpoint)/777")
          return
        }
        let urlRequest = URLRequest(url: url)
        let session = URLSession(configuration: URLSessionConfiguration.default)
        let tSMRFOGICtask = session.dataTask(with: urlRequest) { data , response, error in
          guard error == nil else {
            XCTFail("error calling GET on \(self.collectionsEndpoint)")
            print(error!)
            return
          }
          guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Error: unable to retrieve HTTP Status code")
            return
          }
          XCTAssertEqual(404, httpResponse.statusCode)
          expect404Failure.fulfill()
        }
        tSMRFOGICtask.resume()

        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error)
        }
    }

    func testSMRFailOnPutInvalidCollection() {
        let expect404Failure = expectation(description: "Expect a 400 NOT FOUND response to PUTting a non-existant collection")

        guard let url = URL(string: collectionsEndpoint + "/777") else {
          XCTFail("Error: cannot create URL for \(collectionsEndpoint)/777")
          return
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "PUT"
        let session = URLSession(configuration: URLSessionConfiguration.default)
        let tSMRFOPICtask = session.dataTask(with: urlRequest) { data , response, error in
          guard error == nil else {
            XCTFail("error calling GET on \(self.collectionsEndpoint)")
            print(error!)
            return
          }
          guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Error: unable to retrieve HTTP Status code")
            return
          }
          XCTAssertEqual(404, httpResponse.statusCode)
          expect404Failure.fulfill()
        }
        tSMRFOPICtask.resume()

        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error)
        }
    }

    func testSMRFailOnDeleteInvalidCollection() {
        let expect404Failure = expectation(description: "Expect a 400 NOT FOUND response to DELETEing a non-existant collection")

        guard let url = URL(string: collectionsEndpoint + "/777") else {
          XCTFail("Error: cannot create URL for \(collectionsEndpoint)/777")
          return
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "DELETE"
        let session = URLSession(configuration: URLSessionConfiguration.default)
        let tSMRFODICtask = session.dataTask(with: urlRequest) { data , response, error in
          guard error == nil else {
            XCTFail("error calling GET on \(self.collectionsEndpoint)")
            print(error!)
            return
          }
          guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Error: unable to retrieve HTTP Status code")
            return
          }
          XCTAssertEqual(404, httpResponse.statusCode)
          expect404Failure.fulfill()
        }
        tSMRFODICtask.resume()

        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error)
        }
    }

    func testSMRMultipleHTTPHits() {
        let expectMultipleHits = expectation(description: "Expect 5 hits on the collection URL")

        guard let url = URL(string: collectionsEndpoint) else {
          XCTFail("Error: cannot create URL for \(collectionsEndpoint)")
          return
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        let session = URLSession(configuration: URLSessionConfiguration.default)
        let tSMRMHMtask = session.dataTask(with: urlRequest) { data , response, error in
          guard error == nil else {
            XCTFail("error calling POST on \(self.collectionsEndpoint)")
            print(error!)
            return
          }
          guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Error: unable to retrieve HTTP Status code")
            return
          }
          guard let responseData = data else {
            XCTFail("Error: did not receive data")
            return
          }
          do {
            XCTAssertEqual(201, httpResponse.statusCode)
            let result = try self.decoder.decode(CollectionUri.self, from: responseData)
            let uriString = result.uri
            guard let url2 = URL(string: uriString) else {
              XCTFail("Error: cannot create URL for \(result.uri)")
              return
            }
            var urlRequest2 = URLRequest(url: url2)
            urlRequest2.httpMethod = "GET"
            // generate 5 hits
            for _ in 1...5 {
              let tSMRMHMtask2 = session.dataTask(with: urlRequest2) { _ , _, _ in }
              tSMRMHMtask2.resume()
              sleep(2)
            }
            let tSMRMHMtask3 = session.dataTask(with: urlRequest2) { data , response, error in
              guard error == nil else {
                XCTFail("error calling GET on \(uriString)")
                print(error!)
                return
              }
              guard let httpResponse = response as? HTTPURLResponse else {
                XCTFail("Error: unable to retrieve HTTP Status code")
                return
              }
              guard let responseData = data else {
                XCTFail("Error: did not receive data")
                return
              }
              do {
                XCTAssertEqual(200, httpResponse.statusCode)
                let result = try self.decoder.decode(SMRCollection.self, from: responseData)
                // find report for collection url
                if let report = result.httpUrls.first(where: { $0.url == uriString }) {
                  XCTAssertEqual(5, report.hits, "Expected 5 HTTP hits")
                  expectMultipleHits.fulfill()
                  print("\(result)")
                  // cleanup
                  urlRequest2.httpMethod = "DELETE"
                  let tSMRMHMtask4 = session.dataTask(with: urlRequest2) { _ , _, _ in }
                  tSMRMHMtask4.resume()
                } else {
                  XCTFail("Unable to find any hits for \(uriString)")
                }
              } catch {
                XCTFail("error trying to decode responseData into SMRCollection struct")
                return
              }
            }
            tSMRMHMtask3.resume()
          } catch {
            XCTFail("error trying to decode responseData into CollectionUri struct")
            return
          }
        }
        tSMRMHMtask.resume()

        waitForExpectations(timeout: 20) { error in
            XCTAssertNil(error)
        }
    }

    func testSMRMultiplePOSTCollectionCreations() {
        let expectMultipleCollections = expectation(description: "Expect 3 collections in the collection list")

        guard let url = URL(string: collectionsEndpoint) else {
          XCTFail("Error: cannot create URL for \(collectionsEndpoint)")
          return
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        let session = URLSession(configuration: URLSessionConfiguration.default)
        for _ in 1...3 {
          let tSMRMPCCtask = session.dataTask(with: urlRequest) { _ , response, _ in
            guard let httpResponse = response as? HTTPURLResponse else {
              XCTFail("Error: unable to retrieve HTTP Status code")
              return
            }
            XCTAssertEqual(201, httpResponse.statusCode)
          }
          tSMRMPCCtask.resume()
          sleep(2)
        }
        urlRequest.httpMethod = "GET"
        let tSMRMPCCtask2 = session.dataTask(with: urlRequest) { data , response, error in
          guard error == nil else {
            XCTFail("error calling GET on \(self.collectionsEndpoint)")
            print(error!)
            return
          }
          guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Error: unable to retrieve HTTP Status code")
            return
          }
          guard let responseData = data else {
            XCTFail("Error: did not receive data")
            return
          }
          do {
            XCTAssertEqual(200, httpResponse.statusCode)
            let result = try self.decoder.decode(CollectionsList.self, from: responseData)
            XCTAssertEqual(3, result.collectionUris.count)
            var idArray = ["0", "1", "2"]
            for collectionUriString in result.collectionUris {
              let splitCollectionUriString = collectionUriString.split(separator: "/")
              let collectionUriIDString = String(splitCollectionUriString[splitCollectionUriString.count - 1])
              guard let index = idArray.index(of: collectionUriIDString) else {
                print("\(result)")
                XCTFail("Collection ID \(collectionUriIDString) not in expected range [0-2]")
                return
              }
              idArray.remove(at: index)
              guard let url2 = URL(string: self.collectionsEndpoint + "/" + collectionUriIDString) else {
                XCTFail("Error: cannot create URL for \(self.collectionsEndpoint)/\(collectionUriIDString)")
                return
              }
              var urlRequest2 = URLRequest(url: url2)
              urlRequest2.httpMethod = "DELETE"
              let tSMRMPCCtask3 = session.dataTask(with: urlRequest2) { _ , _, _ in }
              tSMRMPCCtask3.resume()
            }
            XCTAssertTrue(idArray.isEmpty, "Did not encounter all expected Collection IDs")
            expectMultipleCollections.fulfill()
            print("\(result)")
          } catch {
            XCTFail("error trying to decode responseData into CollectionsList struct")
            return
          }
        }
        tSMRMPCCtask2.resume()

        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error)
        }
    }



    static var allTests : [(String, (SwiftMetricsRESTTests) -> () throws -> Void)] {
        return [
          ("SMRNoCollections", testSMRNoCollections),
          ("SMRCollectionCreationAndDeletion", testSMRCollectionCreationAndDeletion),
          ("SMRCollectionContents", testSMRCollectionContents),
          ("SMRResetCollectionOnPut", testSMRResetCollectionOnPut),
          ("SMRFailOnGetInvalidCollection", testSMRFailOnGetInvalidCollection),
          ("SMRFailOnPutInvalidCollection", testSMRFailOnPutInvalidCollection),
          ("SMRFailOnDeleteInvalidCollection", testSMRFailOnDeleteInvalidCollection),
          ("SMRMultipleHTTPHits", testSMRMultipleHTTPHits),
          ("SMRMultiplePOSTCollectionCreations", testSMRMultiplePOSTCollectionCreations),
        ]
    }
}
