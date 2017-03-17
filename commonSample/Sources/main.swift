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

import SwiftMetrics

let sm = try SwiftMetrics()
let monitoring = sm.monitor()

func processCPU(cpu: CPUData) {
   print("\nThis is a custom CPU event response.\n cpu.timeOfSample = \(cpu.timeOfSample), \n cpu.percentUsedByApplication = \(cpu.percentUsedByApplication), \n cpu.percentUsedBySystem = \(cpu.percentUsedBySystem).\n")
}

func processMem(mem: MemData) {
   print("\nThis is a custom Memory event response.\n mem.timeOfSample = \(mem.timeOfSample), \n mem.totalRAMOnSystem = \(mem.totalRAMOnSystem), \n mem.totalRAMUsed = \(mem.totalRAMUsed), \n mem.totalRAMFree = \(mem.totalRAMFree), \n mem.applicationAddressSpaceSize = \(mem.applicationAddressSpaceSize), \n mem.applicationPrivateSize = \(mem.applicationPrivateSize), \n mem.applicationRAMUsed = \(mem.applicationRAMUsed).\n")
}

func processEnv(env: EnvData) {
   print("\nThis is a custom Environment event response.")
   for (key, value) in env.data {
      print(" \(key) = \(value)")
   }
}

func processLatency(lat: LatencyData) {
  print("\nThis is a custom Latency event response.\n lat.timeOfSample = \(lat.timeOfSample), \n lat.duration = \(lat.duration).\n")
}


monitoring.on(processCPU)
monitoring.on(processMem)
monitoring.on(processEnv)
monitoring.on(processLatency)

monitoring.on({ (indata: InitData) in
   print("\n\n+++ Initialized Environment Information +++\n")
   for (key, value) in indata.data {
      print("\(key): \(value)\n")
   }
   print("\n+++ End of Initialized Environment Information +++\n")
})


print("Press any key to stop")
let response = readLine(strippingNewline: true)

