import SwiftMetrics

let sm = try SwiftMetrics()
let monitor = sm.monitor()

func processCPU(cpu: CPUEvent) {
   print("\nThis is a custom CPU event response.\n cpu.time = \(cpu.time),\n cpu.process = \(cpu.process),\n cpu.system = \(cpu.system).\n")
}

func processMem(mem: MemEvent) {
   print("\nThis is a custom Memory event response.\n mem.time = \(mem.time),\n mem.physical_total = \(mem.physical_total),\n mem.physical_used = \(mem.physical_used),\n mem.physical_free = \(mem.physical_free),\n mem.virtual = \(mem.virtual),\n mem.private = \(mem.private),\n mem.physical = \(mem.physical).\n")
}

monitor.on(eventType: "cpu", processCPU)
monitor.on(processMem)

print("Press any key to stop")
let response = readLine(strippingNewline: true)

