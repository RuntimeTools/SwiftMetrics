import SwiftMetrics

let sm = try SwiftMetrics()
let monitoring = sm.monitor()

func processCPU(cpu: CPUEvent) {
   print("\nThis is a custom CPU event response.\n cpu.time = \(cpu.time),\n cpu.process = \(cpu.process),\n cpu.system = \(cpu.system).\n")
}

func processMem(mem: MemEvent) {
   print("\nThis is a custom Memory event response.\n mem.time = \(mem.time),\n mem.physical_total = \(mem.physical_total),\n mem.physical_used = \(mem.physical_used),\n mem.physical_free = \(mem.physical_free),\n mem.virtual = \(mem.virtual),\n mem.private = \(mem.private),\n mem.physical = \(mem.physical).\n")
}

func processEnv(env: EnvEvent) {
   print("\nThis is a custom Environment event response.")
   for (key, value) in env.data {
      print(" \(key) = \(value)")
   }
}


monitoring.on(processCPU)
monitoring.on(processMem)
monitoring.on(processEnv)

monitoring.on({ (_: InitEvent) in
   print("\n\n+++ Initialized Environment Information +++\n")
   let env = monitoring.getEnvironment();
   for (key, value) in env {
      print("\(key): \(value)\n")
   }
   print("\n+++ End of Initialized Environment Information +++\n")
})


print("Press any key to stop")
let response = readLine(strippingNewline: true)

