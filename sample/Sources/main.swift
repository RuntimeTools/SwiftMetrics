import SwiftMetrics

print("Initialising SwiftMetrics class")

let sm = try SwiftMetrics()

print("Initialisation successful - starting SwiftMetrics")
sm.spath(path: "/home/vagrant/SwiftMetrics/sample/.build/debug")
sm.start()

print ("Startup successful - press any key to stop")
let response = readLine(strippingNewline: true)
sm.stop()

print ("SwiftMetrics stopped - bye bye!")
