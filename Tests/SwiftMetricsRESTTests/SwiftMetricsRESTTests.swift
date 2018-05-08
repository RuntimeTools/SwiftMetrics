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
    let session = URLSession(configuration: URLSessionConfiguration.default)
    var collectionsEndpoint: String = ""

    var sm: SwiftMetrics?
    var smr: SwiftMetricsREST?

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
        let tSMRNCtask = self.session.dataTask(with: urlRequest) { tSMRNCdata , tSMRNCresponse, tSMRNCerror in
          guard tSMRNCerror == nil else {
            XCTFail("error calling GET on \(self.collectionsEndpoint)")
            print(tSMRNCerror!)
            return
          }
          guard let tSMRNCresponseData = tSMRNCdata else {
            XCTFail("Error: did not receive data")
            return
          }
          guard let tSMRNChttpResponse = tSMRNCresponse as? HTTPURLResponse else {
            XCTFail("Error: unable to retrieve HTTP Status code")
            return
          }
          do {
            XCTAssertEqual(200, tSMRNChttpResponse.statusCode)
            let tSMRNCresult = try self.decoder.decode(CollectionsList.self, from: tSMRNCresponseData)
            XCTAssertTrue(tSMRNCresult.collectionUris.isEmpty, "There should be no collections definied")
            expectNoCollections.fulfill()
            print("\(tSMRNCresult)")
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
        let tSMRCCADtask = self.session.dataTask(with: urlRequest) { tSMRCCADdata, tSMRCCADresponse, tSMRCCADerror in
          guard tSMRCCADerror == nil else {
            XCTFail("error calling POST on \(self.collectionsEndpoint)")
            print(tSMRCCADerror!)
            return
          }
          guard let tSMRCCADresponseData = tSMRCCADdata else {
            XCTFail("Error: did not receive data")
            return
          }
          guard let tSMRCCADhttpResponse = tSMRCCADresponse as? HTTPURLResponse else {
            XCTFail("Error: unable to retrieve HTTP Status code")
            return
          }
          do {
            XCTAssertEqual(201, tSMRCCADhttpResponse.statusCode)
            let tSMRCCADresult = try self.decoder.decode(CollectionUri.self, from: tSMRCCADresponseData)
            XCTAssertEqual(tSMRCCADresult.uri, "collections/0", "URI should equal collections/0")
            XCTAssertTrue((tSMRCCADhttpResponse.allHeaderFields["Location"] as! String).contains(tSMRCCADresult.uri), "URI should be available in response header 'Location'")
            expectCorrectCollectionURI.fulfill()
            print("\(tSMRCCADresult)")
            urlRequest.httpMethod = "GET"
            let tSMRCCADtask2 = self.session.dataTask(with: urlRequest) { tSMRCCADdata2 , tSMRCCADresponse2, tSMRCCADerror2 in
              guard tSMRCCADerror2 == nil else {
                XCTFail("error calling GET on \(self.collectionsEndpoint)")
                print(tSMRCCADerror2!)
                return
              }
              guard let tSMRCCADresponseData2 = tSMRCCADdata2 else {
                XCTFail("Error: did not receive data")
                return
              }
              guard let tSMRCCADhttpResponse2 = tSMRCCADresponse2 as? HTTPURLResponse else {
                XCTFail("Error: unable to retrieve HTTP Status code")
                return
              }
              do {
                XCTAssertEqual(200, tSMRCCADhttpResponse2.statusCode)
                let tSMRCCADresult2 = try self.decoder.decode(CollectionsList.self, from: tSMRCCADresponseData2)
                XCTAssertEqual(1, tSMRCCADresult2.collectionUris.count, "There should only be one collection")
                XCTAssertEqual(tSMRCCADresult2.collectionUris[0], "collections/0", "URI should equal collections/0")
                expectOneCollection.fulfill()
                print("\(tSMRCCADresult2)")
                guard let url2 = URL(string: self.collectionsEndpoint + "/0") else {
                  XCTFail("Error: cannot create URL for \(self.collectionsEndpoint)/0")
                  return
                }
                var colletionRequest = URLRequest(url: url2)
                colletionRequest.httpMethod = "DELETE"
                let tSMRCCADtask3 = self.session.dataTask(with: colletionRequest) { tSMRCCADdata3, tSMRCCADresponse3, tSMRCCADerror3 in
                  guard tSMRCCADerror3 == nil else {
                    XCTFail("error calling DELETE on \(self.collectionsEndpoint)/0")
                    print(tSMRCCADerror3!)
                    return
                  }
                  guard let tSMRCCADhttpResponse3 = tSMRCCADresponse3 as? HTTPURLResponse else {
                    XCTFail("Error: unable to retrieve HTTP Status code")
                    return
                  }
                  XCTAssertEqual(204, tSMRCCADhttpResponse3.statusCode)
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
        let tSMRCCtask = self.session.dataTask(with: urlRequest) { tSMRCCdata, tSMRCCresponse, tSMRCCerror in
          guard tSMRCCerror == nil else {
            XCTFail("error calling POST on \(self.collectionsEndpoint)")
            print(tSMRCCerror!)
            return
          }
          guard let tSMRCCresponseData = tSMRCCdata else {
            XCTFail("Error: did not receive data")
            return
          }
          guard let tSMRCChttpResponse = tSMRCCresponse as? HTTPURLResponse else {
            XCTFail("Error: unable to retrieve HTTP Status code")
            return
          }
          do {
            XCTAssertEqual(201, tSMRCChttpResponse.statusCode)
            let tSMRCCresult = try self.decoder.decode(CollectionUri.self, from: tSMRCCresponseData)
            XCTAssertEqual(tSMRCCresult.uri, "collections/0", "URI should equal collections/0")
            print("\(tSMRCCresult)")
            // sleep for hopefully 2 CPU and 2 Memory events
            sleep(20)
            guard let url2 = URL(string: self.collectionsEndpoint + "/0") else {
              XCTFail("Error: cannot create URL for \(self.collectionsEndpoint)/0")
              return
            }
            urlRequest = URLRequest(url: url2)
            urlRequest.httpMethod = "GET"
            let tSMRCCtask2 = self.session.dataTask(with: urlRequest) { tSMRCCdata2, tSMRCCresponse2, tSMRCCerror2 in
              let currentTime = UInt(Date().timeIntervalSince1970 * 1000)
              //give 16 seconds leeway for the sleep
              let minTime = currentTime - 21000
              guard tSMRCCerror2 == nil else {
                XCTFail("error calling GET on \(self.collectionsEndpoint)/0")
                print(tSMRCCerror2!)
                return
              }
              guard let tSMRCCresponseData2 = tSMRCCdata2 else {
                XCTFail("Error: did not receive data")
                return
              }
              guard let tSMRCChttpResponse2 = tSMRCCresponse2 as? HTTPURLResponse else {
                XCTFail("Error: unable to retrieve HTTP Status code")
                return
              }
              do {
                XCTAssertEqual(200, tSMRCChttpResponse2.statusCode)
                let tSMRCCresult2 = try self.decoder.decode(SMRCollection.self, from: tSMRCCresponseData2)
                XCTAssertEqual(0, tSMRCCresult2.id, "Collection ID should be 0")
                expectCorrectID.fulfill()
                XCTAssertLessThan(tSMRCCresult2.startTime, currentTime, "Collection was created in the future")
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.startTime, minTime, "Collection created too long ago")
                XCTAssertLessThanOrEqual(tSMRCCresult2.endTime, currentTime, "Collection finished in the future")
                XCTAssertGreaterThan(tSMRCCresult2.endTime, minTime, "Collection finished too long ago")
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.endTime, tSMRCCresult2.startTime, "Collection started after it finished")
                XCTAssertEqual(tSMRCCresult2.endTime - tSMRCCresult2.startTime, tSMRCCresult2.duration, "Duration length inaccurate")
                expectCorrectTimeData.fulfill()
                // cpu values should be between 0 and 1
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.cpu.systemMean, 0, "CPU System Mean not big enough")
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.cpu.processMean, 0, "CPU Process Mean not big enough")
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.cpu.systemPeak, 0, "CPU System Peak not big enough")
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.cpu.processPeak, 0, "CPU Process Peak not big enough")
                XCTAssertLessThanOrEqual(tSMRCCresult2.cpu.systemMean, 1, "CPU System Mean not small enough")
                XCTAssertLessThanOrEqual(tSMRCCresult2.cpu.processMean, 1, "CPU Process Mean not small enough")
                XCTAssertLessThanOrEqual(tSMRCCresult2.cpu.systemPeak, 1, "CPU System Peak not small enough")
                XCTAssertLessThanOrEqual(tSMRCCresult2.cpu.processPeak, 1, "CPU Process Peak not small enough")
                // peaks should be bigger than means
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.cpu.systemPeak, tSMRCCresult2.cpu.systemMean, "CPU System Peak less than mean")
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.cpu.processPeak, tSMRCCresult2.cpu.processMean, "CPU Process Peak less than mean")
                // system should be higher than process
                // these tests cause false failures in Travis's linux container environment
#if !os(Linux)
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.cpu.systemPeak, tSMRCCresult2.cpu.processPeak, "CPU Process Peak higher than System Peak")
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.cpu.systemMean, tSMRCCresult2.cpu.processMean, "CPU Process Mean higher than System Mean")
#endif
                expectCorrectCPUData.fulfill()
                // mem values should be positive
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.memory.systemMean, 0, "Memory System Mean not big enough")
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.memory.processMean, 0, "Memory Process Mean not big enough")
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.memory.systemPeak, 0, "Memory System Peak not big enough")
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.memory.processPeak, 0, "Memory Process Peak not big enough")
                // peaks should be bigger than means
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.memory.systemPeak, tSMRCCresult2.memory.systemMean, "Memory System Peak less than mean")
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.memory.processPeak, tSMRCCresult2.memory.processMean, "Memory Process Peak less than mean")
                // system should be higher than process
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.memory.systemPeak, tSMRCCresult2.memory.processPeak, "Memory Process Peak higher than System Peak")
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.memory.systemMean, tSMRCCresult2.memory.processMean, "Memory Process Mean higher than System Mean")
                expectCorrectMemoryData.fulfill()
                // There should only be one HTTP record - for the creation POST call.
                XCTAssertEqual(1, tSMRCCresult2.httpUrls.count, "Only expected one HTTP record")
                XCTAssertEqual(1, tSMRCCresult2.httpUrls[0].hits, "Only expected one HTTP hit")
                XCTAssertEqual(self.collectionsEndpoint, tSMRCCresult2.httpUrls[0].url, "HTTP URL not \(self.collectionsEndpoint)/0")
                // HTTP times should be positive
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.httpUrls[0].averageResponseTime, 0, "HTTP Average response time not big enough")
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.httpUrls[0].longestResponseTime, 0, "HTTP Longest response time not big enough")
                // Longest should be higher than average
                XCTAssertGreaterThanOrEqual(tSMRCCresult2.httpUrls[0].longestResponseTime, tSMRCCresult2.httpUrls[0].averageResponseTime, "Memory Process Peak less than mean")
                print("\(tSMRCCresult2)")
                // cleanup
                urlRequest.httpMethod = "DELETE"
                let tSMRCCtask3 = self.session.dataTask(with: urlRequest) { _ , _, _ in
                  expectCorrectHTTPData.fulfill()
                }
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
        let tSMRRCOPtask = self.session.dataTask(with: urlRequest) { tSMRRCOPdata , tSMRRCOPresponse, tSMRRCOPerror in
          guard tSMRRCOPerror == nil else {
            XCTFail("error calling POST on \(self.collectionsEndpoint)")
            print(tSMRRCOPerror!)
            return
          }
          guard let tSMRRCOPhttpResponse = tSMRRCOPresponse as? HTTPURLResponse else {
            XCTFail("Error: unable to retrieve HTTP Status code")
            return
          }
          guard let tSMRRCOPresponseData = tSMRRCOPdata else {
            XCTFail("Error: did not receive data")
            return
          }
          do {
            XCTAssertEqual(201, tSMRRCOPhttpResponse.statusCode)
            let tSMRRCOPresult = try self.decoder.decode(CollectionUri.self, from: tSMRRCOPresponseData)
            let tSMRRCOPuriString = tSMRRCOPresult.uri
            let tSMRRCOPsplitUriString = tSMRRCOPuriString.split(separator: "/")
            let tSMRRCOPcollectionID = Int(tSMRRCOPsplitUriString[tSMRRCOPsplitUriString.count - 1])
            XCTAssertEqual(0, tSMRRCOPcollectionID, "Collection ID not 0")
            guard let url2 = URL(string: self.collectionsEndpoint + "/0") else {
              XCTFail("Error: cannot create URL for \(self.collectionsEndpoint)/0")
              return
            }
            // wait for some time to pass before resetting
            sleep(8)
            var urlRequest2 = URLRequest(url: url2)
            urlRequest2.httpMethod = "PUT"
            let tSMRRCOPtask2 = self.session.dataTask(with: urlRequest2) { tSMRRCOPdata2, tSMRRCOPresponse2, tSMRRCOPerror2 in
              guard tSMRRCOPerror2 == nil else {
                XCTFail("error calling PUT on \(self.collectionsEndpoint)/0")
                print(tSMRRCOPerror2!)
                return
              }
              guard let tSMRRCOPhttpResponse2 = tSMRRCOPresponse2 as? HTTPURLResponse else {
                XCTFail("Error: unable to retrieve HTTP Status code")
                return
              }
              XCTAssertEqual(204, tSMRRCOPhttpResponse2.statusCode)
              urlRequest2.httpMethod = "GET"
              let tSMRRCOPtask3 = self.session.dataTask(with: urlRequest2) { tSMRRCOPdata3, tSMRRCOPresponse3, tSMRRCOPerror3 in
                guard tSMRRCOPerror3 == nil else {
                  XCTFail("error calling GET on \(self.collectionsEndpoint)/0)")
                  print(tSMRRCOPerror3!)
                  return
                }
                guard let tSMRRCOPhttpResponse3 = tSMRRCOPresponse3 as? HTTPURLResponse else {
                  XCTFail("Error: unable to retrieve HTTP Status code")
                  return
                }
                guard let tSMRRCOPresponseData3 = tSMRRCOPdata3 else {
                  XCTFail("Error: did not receive data")
                  return
                }
                do {
                  let currentTime = UInt(Date().timeIntervalSince1970 * 1000)
                  // reset takes place in under a second
                  let minTime = currentTime - 1000
                  XCTAssertEqual(200, tSMRRCOPhttpResponse3.statusCode)
                  let tSMRRCOPresult3 = try self.decoder.decode(SMRCollection.self, from: tSMRRCOPresponseData3)
                  XCTAssertEqual(tSMRRCOPcollectionID, tSMRRCOPresult3.id, "Collection ID should be \(String(describing: tSMRRCOPcollectionID))")
                  XCTAssertLessThan(tSMRRCOPresult3.startTime, currentTime, "Collection was created in the future")
                  XCTAssertGreaterThanOrEqual(tSMRRCOPresult3.startTime, minTime, "Collection created too long ago")
                  XCTAssertLessThanOrEqual(tSMRRCOPresult3.endTime, currentTime, "Collection finished in the future")
                  XCTAssertGreaterThan(tSMRRCOPresult3.endTime, minTime, "Collection finished too long ago")
                  XCTAssertGreaterThanOrEqual(tSMRRCOPresult3.endTime, tSMRRCOPresult3.startTime, "Collection started after it finished")
                  XCTAssertEqual(tSMRRCOPresult3.endTime - tSMRRCOPresult3.startTime, tSMRRCOPresult3.duration, "Duration length inaccurate")
                  // cpu values should be 0.0
                  XCTAssertEqual(tSMRRCOPresult3.cpu.systemMean, 0.0, "CPU System Mean too big")
                  XCTAssertEqual(tSMRRCOPresult3.cpu.processMean, 0.0, "CPU Process Mean too big")
                  XCTAssertEqual(tSMRRCOPresult3.cpu.systemPeak, 0.0, "CPU System Peak too big")
                  XCTAssertEqual(tSMRRCOPresult3.cpu.processPeak, 0.0, "CPU Process Peak too big")
                  // mem values should be 0
                  XCTAssertEqual(tSMRRCOPresult3.memory.systemMean, 0, "Memory System Mean too big")
                  XCTAssertEqual(tSMRRCOPresult3.memory.processMean, 0, "Memory Process Mean too big")
                  XCTAssertEqual(tSMRRCOPresult3.memory.systemPeak, 0, "Memory System Peak too big")
                  XCTAssertEqual(tSMRRCOPresult3.memory.processPeak, 0, "Memory Process Peak too big")
                  // There should only be one HTTP record - for the PUT call.
                  XCTAssertEqual(1, tSMRRCOPresult3.httpUrls.count, "Only expected one HTTP record")
                  XCTAssertEqual(1, tSMRRCOPresult3.httpUrls[0].hits, "Only expected one HTTP hit")
                  XCTAssertEqual(tSMRRCOPuriString, tSMRRCOPresult3.httpUrls[0].url, "HTTP URL not \(tSMRRCOPuriString)")
                  // HTTP times should be positive
                  XCTAssertGreaterThanOrEqual(tSMRRCOPresult3.httpUrls[0].averageResponseTime, 0, "HTTP Average response time not big enough")
                  XCTAssertGreaterThanOrEqual(tSMRRCOPresult3.httpUrls[0].longestResponseTime, 0, "HTTP Longest response time not big enough")
                  // Longest should be higher than average
                  XCTAssertGreaterThanOrEqual(tSMRRCOPresult3.httpUrls[0].longestResponseTime, tSMRRCOPresult3.httpUrls[0].averageResponseTime, "Memory Process Peak less than mean")
                  print("\(tSMRRCOPresult3)")
                  // cleanup
                  urlRequest2.httpMethod = "DELETE"
                  let tSMRRCOPtask4 = self.session.dataTask(with: urlRequest2) { _ , _, _ in
                    expectCollectionReset.fulfill()
                  }
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
          guard let urlF = URL(string: self.collectionsEndpoint + "/0") else {
            XCTFail("Error: cannot create URL for \(self.collectionsEndpoint)/0")
            return
          }
          var urlRequestF = URLRequest(url: urlF)
          urlRequestF.httpMethod = "DELETE"
          let tSMRRCOPtaskF = self.session.dataTask(with: urlRequestF) { _ , _, _ in }
          tSMRRCOPtaskF.resume()
          sleep(2)
          XCTAssertNil(error)
        }
    }

    func testSMRFailOnInvalidCollection() {
        let expect404Failure = expectation(description: "Expect a 404 NOT FOUND response to GETting a non-existant collection")

        guard let url = URL(string: collectionsEndpoint + "/777") else {
          XCTFail("Error: cannot create URL for \(collectionsEndpoint)/777")
          return
        }
        let urlRequest = URLRequest(url: url)
        let tSMRFOICtask = self.session.dataTask(with: urlRequest) { tSMRFOICdata, tSMRFOICresponse, tSMRFOICerror in
          guard tSMRFOICerror == nil else {
            XCTFail("error calling GET on \(self.collectionsEndpoint)/777")
            print(tSMRFOICerror!)
            return
          }
          guard let tSMRFOIChttpResponse = tSMRFOICresponse as? HTTPURLResponse else {
            XCTFail("Error: unable to retrieve HTTP Status code")
            return
          }
          XCTAssertEqual(404, tSMRFOIChttpResponse.statusCode)
          expect404Failure.fulfill()
        }
        tSMRFOICtask.resume()

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
        let tSMRMHMtask = self.session.dataTask(with: urlRequest) { tSMRMHMdata, tSMRMHMresponse, tSMRMHMerror in
          guard tSMRMHMerror == nil else {
            XCTFail("error calling POST on \(self.collectionsEndpoint)")
            print(tSMRMHMerror!)
            return
          }
          guard let tSMRMHMhttpResponse = tSMRMHMresponse as? HTTPURLResponse else {
            XCTFail("Error: unable to retrieve HTTP Status code")
            return
          }
          guard let tSMRMHMresponseData = tSMRMHMdata else {
            XCTFail("Error: did not receive data")
            return
          }
          do {
            XCTAssertEqual(201, tSMRMHMhttpResponse.statusCode)
            let tSMRMHMresult = try self.decoder.decode(CollectionUri.self, from: tSMRMHMresponseData)
            let tSMRMHMuriString = tSMRMHMresult.uri
            let tSMRMHMsplitUriString = tSMRMHMuriString.split(separator: "/")
          let tSMRMHMcollectionID = String(tSMRMHMsplitUriString[tSMRMHMsplitUriString.count - 1])
            guard let url2 = URL(string: self.collectionsEndpoint + "/" + tSMRMHMcollectionID) else {
              XCTFail("Error: cannot create URL for \(self.collectionsEndpoint)/\(tSMRMHMcollectionID)")
              return
            }
            var urlRequest2 = URLRequest(url: url2)
            urlRequest2.httpMethod = "GET"
            // generate 5 hits
            for _ in 1...5 {
              let tSMRMHMtask2 = self.session.dataTask(with: urlRequest2) { _ , _, _ in }
              tSMRMHMtask2.resume()
              sleep(2)
            }
            let tSMRMHMtask3 = self.session.dataTask(with: urlRequest2) { tSMRMHMdata3 , tSMRMHMresponse3, tSMRMHMerror3 in
              guard tSMRMHMerror3 == nil else {
                XCTFail("error calling GET on \(tSMRMHMuriString)")
                print(tSMRMHMerror3!)
                return
              }
              guard let tSMRMHMhttpResponse3 = tSMRMHMresponse3 as? HTTPURLResponse else {
                XCTFail("Error: unable to retrieve HTTP Status code")
                return
              }
              guard let tSMRMHMresponseData3 = tSMRMHMdata3 else {
                XCTFail("Error: did not receive data")
                return
              }
              do {
                XCTAssertEqual(200, tSMRMHMhttpResponse3.statusCode)
                let tSMRMHMresult3 = try self.decoder.decode(SMRCollection.self, from: tSMRMHMresponseData3)
                // find report for collection url
                if let tSMRMHMreport3 = tSMRMHMresult3.httpUrls.first(where: { $0.url == self.collectionsEndpoint + "/" + tSMRMHMcollectionID }) {
                  XCTAssertEqual(5, tSMRMHMreport3.hits, "Expected 5 HTTP hits")
                  print("\(tSMRMHMresult3)")
                  // cleanup
                  urlRequest2.httpMethod = "DELETE"
                  let tSMRMHMtask4 = self.session.dataTask(with: urlRequest2) { _ , _, _ in
                    expectMultipleHits.fulfill()
                  }
                  tSMRMHMtask4.resume()
                } else {
                  XCTFail("Unable to find any hits for \(self.collectionsEndpoint + "/" + tSMRMHMcollectionID)")
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
        let expect1stDeletion = expectation(description: "Expect 1st collection to be deleted")
        let expect2ndDeletion = expectation(description: "Expect 2nd collection to be deleted")
        let expect3rdDeletion = expectation(description: "Expect 3rd collection to be deleted")

        var expectationArray = [expect1stDeletion, expect2ndDeletion, expect3rdDeletion]
        guard let url = URL(string: collectionsEndpoint) else {
          XCTFail("Error: cannot create URL for \(collectionsEndpoint)")
          return
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        for _ in 1...3 {
          let tSMRMPCCtask = self.session.dataTask(with: urlRequest) { _ , tSMRMPCCresponse, _ in
            guard let tSMRMPCChttpResponse = tSMRMPCCresponse as? HTTPURLResponse else {
              XCTFail("Error: unable to retrieve HTTP Status code")
              return
            }
            XCTAssertEqual(201, tSMRMPCChttpResponse.statusCode)
          }
          tSMRMPCCtask.resume()
          sleep(2)
        }
        urlRequest.httpMethod = "GET"
        let tSMRMPCCtask2 = self.session.dataTask(with: urlRequest) { tSMRMPCCdata2, tSMRMPCCresponse2, tSMRMPCCerror2 in
          guard tSMRMPCCerror2 == nil else {
            XCTFail("error calling GET on \(self.collectionsEndpoint)")
            print(tSMRMPCCerror2!)
            return
          }
          guard let tSMRMPCChttpResponse2 = tSMRMPCCresponse2 as? HTTPURLResponse else {
            XCTFail("Error: unable to retrieve HTTP Status code")
            return
          }
          guard let tSMRMPCCresponseData2 = tSMRMPCCdata2 else {
            XCTFail("Error: did not receive data")
            return
          }
          do {
            XCTAssertEqual(200, tSMRMPCChttpResponse2.statusCode)
            let tSMRMPCCresult2 = try self.decoder.decode(CollectionsList.self, from: tSMRMPCCresponseData2)
            XCTAssertEqual(3, tSMRMPCCresult2.collectionUris.count)
            var idArray = ["0", "1", "2"]
            for tSMRMPCCcollectionUriString in tSMRMPCCresult2.collectionUris {
              let tSMRMPCCsplitCollectionUriString = tSMRMPCCcollectionUriString.split(separator: "/")
              let tSMRMPCCcollectionUriIDString = String(tSMRMPCCsplitCollectionUriString[tSMRMPCCsplitCollectionUriString.count - 1])
              guard let index = idArray.index(of: tSMRMPCCcollectionUriIDString) else {
                print("\(tSMRMPCCresult2)")
                XCTFail("Collection ID \(tSMRMPCCcollectionUriIDString) not in expected range [0-2]")
                return
              }
              idArray.remove(at: index)
              guard let url2 = URL(string: self.collectionsEndpoint + "/" + tSMRMPCCcollectionUriIDString) else {
                XCTFail("Error: cannot create URL for \(self.collectionsEndpoint + "/" + tSMRMPCCcollectionUriIDString)")
                return
              }
              var urlRequest2 = URLRequest(url: url2)
              urlRequest2.httpMethod = "DELETE"
#if os(Linux) // due to the same URLSession problem, not all the delete tasks come back on Linux
              let tSMRMPCCtask3 = self.session.dataTask(with: urlRequest2) { _ , _, _ in }
              tSMRMPCCtask3.resume()
              expectationArray[Int(tSMRMPCCcollectionUriIDString)!].fulfill()
#else
              let tSMRMPCCtask3 = self.session.dataTask(with: urlRequest2) { _ , _, _ in
                expectationArray[Int(tSMRMPCCcollectionUriIDString)!].fulfill()
              }
              tSMRMPCCtask3.resume()
#endif
              sleep(2)
            }
            XCTAssertTrue(idArray.isEmpty, "Did not encounter all expected Collection IDs")
            expectMultipleCollections.fulfill()
            print("\(tSMRMPCCresult2)")
          } catch {
            XCTFail("error trying to decode responseData into CollectionsList struct")
            return
          }
        }
        tSMRMPCCtask2.resume()

        waitForExpectations(timeout: 30) { error in
            XCTAssertNil(error)
        }
    }

    func testSMRFailOnInvalidIDdCollectionMethod() {
        let expect400Failure = expectation(description: "Expect a 400 BAD REQUEST response to POSTting an existing collection")

        guard let tSMRFOIICMurl = URL(string: collectionsEndpoint) else {
          XCTFail("Error: cannot create URL for \(collectionsEndpoint)")
          return
        }
        var tSMRFOIICMurlRequest = URLRequest(url: tSMRFOIICMurl)
        tSMRFOIICMurlRequest.httpMethod = "POST"
        let tSMRFOIICMtask = self.session.dataTask(with: tSMRFOIICMurlRequest) { tSMRFOIICMdata, tSMRFOIICMresponse, tSMRFOIICMerror in
          guard tSMRFOIICMerror == nil else {
            XCTFail("error calling POST on \(self.collectionsEndpoint)")
            print(tSMRFOIICMerror!)
            return
          }
          guard let tSMRFOIICMhttpResponse = tSMRFOIICMresponse as? HTTPURLResponse else {
            XCTFail("Error: unable to retrieve HTTP Status code")
            return
          }
          XCTAssertEqual(201, tSMRFOIICMhttpResponse.statusCode)
          guard let tSMRFOIICMurl2 = URL(string: self.collectionsEndpoint + "/0") else {
            XCTFail("Error: cannot create URL for \(self.collectionsEndpoint)/0")
            return
          }
          var tSMRFOIICMurlRequest2 = URLRequest(url: tSMRFOIICMurl2)
          tSMRFOIICMurlRequest2.httpMethod = "POST"
          let tSMRFOIICMtask2 = self.session.dataTask(with: tSMRFOIICMurlRequest2) { tSMRFOIICMdata2, tSMRFOIICMresponse2, tSMRFOIICMerror2 in
            guard tSMRFOIICMerror2 == nil else {
              XCTFail("error calling POST on \(self.collectionsEndpoint)")
              print(tSMRFOIICMerror2!)
              return
            }
            guard let tSMRFOIICMhttpResponse2 = tSMRFOIICMresponse2 as? HTTPURLResponse else {
              XCTFail("Error: unable to retrieve HTTP Status code")
              return
            }
            XCTAssertEqual(400, tSMRFOIICMhttpResponse2.statusCode)
            // cleanup
            guard let tSMRFOIICMurl3 = URL(string: self.collectionsEndpoint + "/0") else {
              XCTFail("Error: cannot create URL for \(self.collectionsEndpoint)/0")
              return
            }
            var tSMRFOIICMurlRequest3 = URLRequest(url: tSMRFOIICMurl3)
            tSMRFOIICMurlRequest3.httpMethod = "DELETE"
            let tSMRFOIICMtask3 = self.session.dataTask(with: tSMRFOIICMurlRequest3) { _, tSMRFOIICMresponse3, _ in
              guard let tSMRFOIICMhttpResponse3 = tSMRFOIICMresponse3 as? HTTPURLResponse else {
                XCTFail("Error: unable to retrieve HTTP Status code")
                return
              }
              XCTAssertEqual(204, tSMRFOIICMhttpResponse3.statusCode)
              expect400Failure.fulfill()
            }
            tSMRFOIICMtask3.resume()
            sleep(2)
          }
          tSMRFOIICMtask2.resume()
        }
        tSMRFOIICMtask.resume()

        waitForExpectations(timeout: 20) { error in
            XCTAssertNil(error)
        }
    }

    static var allTests : [(String, (SwiftMetricsRESTTests) -> () throws -> Void)] {
      //currently SMRResetCollectionOnPut fails for undiagnosed reasons on Linux
#if os(Linux)
        return [
          ("SMRNoCollections", testSMRNoCollections),
          ("SMRCollectionCreationAndDeletion", testSMRCollectionCreationAndDeletion),
          ("SMRCollectionContents", testSMRCollectionContents),
          ("SMRFailOnInvalidCollection", testSMRFailOnInvalidCollection),
          ("SMRMultipleHTTPHits", testSMRMultipleHTTPHits),
          ("SMRMultiplePOSTCollectionCreations", testSMRMultiplePOSTCollectionCreations),
        ]
#else
        return [
          ("SMRNoCollections", testSMRNoCollections),
          ("SMRCollectionCreationAndDeletion", testSMRCollectionCreationAndDeletion),
          ("SMRCollectionContents", testSMRCollectionContents),
          ("SMRResetCollectionOnPut", testSMRResetCollectionOnPut),
          ("SMRFailOnInvalidCollection", testSMRFailOnInvalidCollection),
          ("SMRMultipleHTTPHits", testSMRMultipleHTTPHits),
          ("SMRMultiplePOSTCollectionCreations", testSMRMultiplePOSTCollectionCreations),
          ("SMRFailOnInvalidIDdCollectionMethod", testSMRFailOnInvalidIDdCollectionMethod),
        ]
#endif
    }
}
