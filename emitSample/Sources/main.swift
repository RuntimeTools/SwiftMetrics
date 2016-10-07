import SwiftMetrics
import Foundation
import Dispatch

let sm = try SwiftMetrics()
let monitoring = sm.monitor()

public class AlarmClock {

   private let alarmTime: Date
   private var snoozeInterval : Int
   private var endAlarm = false

   public init(time: Date, snooze: Int) {
      self.snoozeInterval = snooze
      self.alarmTime = time
      monitoring.on(dataType: "snooze", snoozeMessage)
   }

   public convenience init(time: Date) {
      self.init(time: time, snooze: 5)
   }

   public func stop() {
      print("Stopping alarm")
      endAlarm=true
   }

   private func snoozeMessage(data: Any) -> () {
      print("\nAlarm has been ignored for \(data as! Int * snoozeInterval) seconds!\n")
   }

   public func waitForAlarm() {
      print("Waiting for alarm to go off....")
      var timeNow = Date()
      while timeNow.compare(alarmTime) == ComparisonResult.orderedAscending {
         sleep(1)
         timeNow = Date()
      }
      soundTheAlarm()
      snooze()
   }

   private func soundTheAlarm() {
      print("\nALARM! ALARM! ALARM! ALARM!\n")
      print("Press Enter to stop the alarm")
   }

   private func snooze() {
      var i = 1
      while !endAlarm {
         sleep(UInt32(snoozeInterval))
         sm.emitData(ofType: "snooze", i as Any)  
         i += 1
      }
      print("Alarm stopped - have a nice day!")
   }

}

let myAC = AlarmClock(time: Date(timeIntervalSinceNow: 5))
DispatchQueue.global(qos: .background).async {
   myAC.waitForAlarm()
}
let response = readLine(strippingNewline: true)
myAC.stop()
