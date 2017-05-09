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
                print("\nThis is a custom CPU event response.\n cpu.timeOfSample = \(cpu.timeOfSample), \n cpu.percentUsedByApplication = \(cpu.percentUsedByApplication), \n cpu.percentUsedBySystem = \(cpu.percentUsedBySystem).\n")
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

        func processInit(env: InitData) {
            if(!fulfilled) {
                print("\nThis is a custom Environment event response.")
                for (key, value) in env.data {
                   print(" \(key) = \(value)")
                }
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
                print("\nThis is a custom Memory event response.\n mem.timeOfSample = \(mem.timeOfSample), \n mem.totalRAMOnSystem = \(mem.totalRAMOnSystem), \n mem.totalRAMUsed = \(mem.totalRAMUsed), \n mem.totalRAMFree = \(mem.totalRAMFree), \n mem.applicationAddressSpaceSize = \(mem.applicationAddressSpaceSize), \n mem.applicationPrivateSize = \(mem.applicationPrivateSize), \n mem.applicationRAMUsed = \(mem.applicationRAMUsed).\n")
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

        sm!.stop()
        monitoring = sm!.monitor()

        sm!.stop()
        monitoring = sm!.monitor()

        sm!.stop()
        monitoring = sm!.monitor()

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
