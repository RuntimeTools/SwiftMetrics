import SwiftMetrics

print("Initialising SwiftMetrics class")

let sm = SwiftMetrics()

print("Initialisation successful - starting SwiftMetrics")
//sm.spath(path: "/vagrant/deploy/plugins")
sm.start()

print ("Startup successful - press any key to stop")
let response = readLine(strippingNewline: true)
sm.stop()

print ("SwiftMetrics stopped - bye bye!")
