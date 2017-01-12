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


monitoring.on(processCPU)
monitoring.on(processMem)
monitoring.on(processEnv)

monitoring.on({ (in: InitData) in
   print("\n\n+++ Initialized Environment Information +++\n")
   for (key, value) in in.data {
      print("\(key): \(value)\n")
   }
   print("\n+++ End of Initialized Environment Information +++\n")
})


print("Press any key to stop")
let response = readLine(strippingNewline: true)

