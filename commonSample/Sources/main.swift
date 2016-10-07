import SwiftMetrics

let sm = try SwiftMetrics()
let monitoring = sm.monitor()

func processCPU(cpu: CPUData) {
   print("\nThis is a custom CPU event response.\n cpu.timeOfSample = \(cpu.timeOfSample), \n cpu.percentUsedByApplication = \(cpu.percentUsedByApplication), \n cpu.percentUsedBySystem = \(cpu.percentUsedBySystem).\n")
}

func processMem(mem: MemData) {
   print("\nThis is a custom Memory event response.\n mem.timeOfSample = \(mem.timeOfSample), \n mem.totalRAMOnSystem = \(mem.totalRAMOnSystem), \n mem.totalRAMUsed = \(mem.totalRAMUsed), \n mem.totalRAMFree = \(mem.totalRAMFree), \n mem.applicationAddressSpaceSize = \(mem.applicationAddressSpaceSize), \n mem.applicationPrivateSize = \(mem.applicationPrivateSize), \n mem.applicationRAMUsed = \(mem.applicationRAMUsed).\n")
}

func processEnv(env: [ String : String ]) {
   print("\nThis is a custom Environment event response.")
   for (key, value) in env {
      print(" \(key) = \(value)")
   }
}


monitoring.on(dataType: "cpu", processCPU)
monitoring.on(processMem)
monitoring.on(dataType: "environment", processEnv)

monitoring.on(dataType: "initialized", { (_: [ String : String ]) in
   print("\n\n+++ Initialized Environment Information +++\n")
   let env = monitoring.getEnvironmentData();
   for (key, value) in env {
      print("\(key): \(value)\n")
   }
   print("\n+++ End of Initialized Environment Information +++\n")
})


print("Press any key to stop")
let response = readLine(strippingNewline: true)

