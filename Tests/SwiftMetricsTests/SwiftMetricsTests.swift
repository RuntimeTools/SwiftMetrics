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
@testable import SwiftMetrics

class SwiftMetricsTests: XCTestCase {

    var sm: SwiftMetrics?
    var monitoring: SwiftMonitor?

    override func setUp() {
        super.setUp()

        do {
            sm = try SwiftMetrics()
            XCTAssertNotNil(sm, "Cannot find SwiftMetrics instance")
            monitoring = sm!.monitor()
            XCTAssertNotNil(monitoring, "Cannot find SwiftMonitor instance")
        } catch {
            XCTFail("Unable to instantiate SwiftMetrics")
        }
    }

    override func tearDown() {
        super.tearDown()
        sm!.stop()
        monitoring = nil
        sm = nil
    }

    func testSwiftMetricsCPU() {
        let expectCPU = expectation(description: "Expect a CPU event")
        var fulfilled = false;

        func processCPU(cpu: CPUData) {
            if(!fulfilled) {
 					      XCTAssertNotNil(cpu, "CPU Data should not be nil")
                XCTAssertGreaterThan(cpu.timeOfSample, 0, " cpu.timeOfSample = \(cpu.timeOfSample), should be greater than zero")
                XCTAssertGreaterThan(cpu.percentUsedByApplication, 0, " cpu.percentUsedByApplication = \(cpu.percentUsedByApplication), should be greater than zero")
                XCTAssertGreaterThan(cpu.percentUsedBySystem, 0, " cpu.percentUsedBySystem = \(cpu.percentUsedBySystem), should be greater than zero")
                XCTAssertLessThan(cpu.percentUsedByApplication, 100, " cpu.percentUsedByApplication = \(cpu.percentUsedByApplication), should be less than 100")
                XCTAssertLessThan(cpu.percentUsedBySystem, 100, " cpu.percentUsedBySystem = \(cpu.percentUsedBySystem), should be less than 100")
                expectCPU.fulfill()
                fulfilled = true;
            }
        }

        monitoring!.on(processCPU)

        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error)
        }
    }

    func testSwiftMetricsInit() {
        let expectInit = expectation(description: "Expect an Init event")
        var fulfilled = false;

        func processInit(initData: InitData) {
            if(!fulfilled) {
 					      XCTAssertNotNil(initData, "InitData should not be nil")
 					      XCTAssertNotNil(initData.data, "InitData.data should not be nil")
                XCTAssertGreaterThan(initData.data.count, 0, "InitData.data should contain some environment variables")
                expectInit.fulfill()
                fulfilled = true;
            }
        }

        monitoring!.on(processInit)

        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error)
        }
    }

    func testSwiftMetricsEnv() {
        let expectEnv = expectation(description: "Expect an Environment event")
        var fulfilled = false;

        func processEnv(env: EnvData) {
            if(!fulfilled) {
 					      XCTAssertNotNil(env, "EnvData should not be nil")
 					      XCTAssertNotNil(env.data, "EnvData.data should not be nil")
                XCTAssertGreaterThan(env.data.count, 0, "EnvData.data should contain some environment variables")
                expectEnv.fulfill()
                fulfilled = true;
            }
        }

        monitoring!.on(processEnv)

        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error)
        }
    }


    func testSwiftMetricsMemory() {
        let expectMem = expectation(description: "Expect a Memory event")
        var fulfilled = false;

        func processMem(mem: MemData) {
            if(!fulfilled) {
 					  XCTAssertNotNil(mem, "MemData should not be nil")
                XCTAssertGreaterThan(mem.timeOfSample, 0, "mem.timeOfSample = \(mem.timeOfSample), should be greater than zero")
                XCTAssertGreaterThan(mem.totalRAMOnSystem, 0, "mem.totalRAMOnSystem = \(mem.totalRAMOnSystem), should be greater than zero")
                XCTAssertGreaterThan(mem.totalRAMUsed, 0, "mem.totalRAMUsed = \(mem.totalRAMUsed), should be greater than zero")
                XCTAssertGreaterThan(mem.totalRAMFree, 0, "mem.totalRAMFree = \(mem.totalRAMFree), should be greater than zero")
                XCTAssertGreaterThan(mem.applicationAddressSpaceSize, 0, "mem.applicationAddressSpaceSize = \(mem.applicationAddressSpaceSize), should be greater than zero")
              // TODO: This fails intermittently on the Mac, sometimes -1 is returned
              //  XCTAssertGreaterThan(mem.applicationPrivateSize, 0, "mem.applicationPrivateSize = \(mem.applicationPrivateSize), should be greater than zero")
                XCTAssertGreaterThan(mem.applicationRAMUsed, 0, "mem.applicationRAMUsed = \(mem.applicationRAMUsed), should be greater than zero")
                expectMem.fulfill()
                fulfilled = true;
            }
        }

        monitoring!.on(processMem)

        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error)
        }
    }

   func testSwiftMetricsLatency() {
       let expectLatency = expectation(description: "Expect a latency event")
       var fulfilled = false;

       func processLatency(latency: LatencyData) {
           if(!fulfilled) {
               XCTAssertNotNil(latency, "Latency Data should not be nil")
               XCTAssertGreaterThanOrEqual(latency.duration, 0, " latency.duration = \(latency.duration), should be greater than or equal to zero")
               XCTAssertLessThan(latency.duration, 1, " latency.duration = \(latency.duration), should be less than one")
               XCTAssertGreaterThan(latency.timeOfSample, 0, " latency.timeOfSample = \(latency.timeOfSample), should be greater than zero")
               fulfilled = true
               expectLatency.fulfill()
           }
       }

       monitoring!.on(processLatency)
       waitForExpectations(timeout: 10) { error in
          XCTAssertNil(error)
       }
   }

    func testSwiftMetricsLifecycle() {
        let expectCPU = expectation(description: "Expect a CPU event after stop and restart")
        var fulfilled = false;

        func processCPU(cpu: CPUData) {
            if(!fulfilled) {
                fulfilled = true
                expectCPU.fulfill()
            }
        }

        sm!.stop()
        monitoring = sm!.monitor()

        monitoring!.on(processCPU)
        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error)
        }
    }

    static var allTests : [(String, (SwiftMetricsTests) -> () throws -> Void)] {
        return [
            ("SwiftMetricsInit", testSwiftMetricsInit),
            ("SwiftMetricsCPU", testSwiftMetricsCPU),
            ("SwiftMetricsLatency", testSwiftMetricsLatency),
            ("SwiftMetricsMemory", testSwiftMetricsMemory),
            ("SwiftMetricsLifecycle", testSwiftMetricsLifecycle),
            ("SwiftMetricsEnv", testSwiftMetricsEnv)
        ]
    }
}
