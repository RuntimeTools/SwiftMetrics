/**
 * Copyright IBM Corporation 2016
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

import SwiftMetricsKitura
import SwiftMetrics
import Foundation
import HeliumLogger
import LoggerAPI

public class SwiftDataCollector {

    public var monitor:SwiftMonitor
    public var swMetricInstance:SwiftMetrics

    var logLevel : LoggerMessageType = .info
    var swiftDataCollectorInited = false
    var envData: [String:String]!
    var vcapAppDictionary : [String: Any]!
    var applicationName: String = ""

    var formatter = DateFormatter()
    var cpuSampleTime: TimeInterval = 0
    var memSampleTime: TimeInterval = 0

    var appResourceID: String!
    var osResourceID: String!
    var origin: String!
    var tenant: String!
    var registeredResources: Bool = false


    let bamConfig = BMConfig.sharedInstance

    public init(swiftMetricsInstance : SwiftMetrics) throws {

        self.logLevel = self.bamConfig.logLevel
        HeliumLogger.use(self.logLevel)
        print("[SwiftDataCollector] found it")
        self.formatter.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'SSS'Z'"
        self.formatter.timeZone = TimeZone(abbreviation: "UTC") as TimeZone!

        self.appResourceID = self.bamConfig.appId
        self.origin = self.bamConfig.dcId
        self.tenant = self.bamConfig.tenantId
        self.osResourceID = self.bamConfig.getResourceId(resName: "osID")

        self.swMetricInstance = swiftMetricsInstance
        self.monitor = swiftMetricsInstance.monitor()

        monitor.on({ (_: InitData) in
            self.envInitandTopoRegister()
            self.registeredResources = true
        })

        _ = SwiftMetricsKitura(swiftMetricsInstance: swiftMetricsInstance)

        Log.info("SwiftDataCollector init: origin = \(origin!), appResourceID = \(appResourceID!), osResourceID = \(osResourceID!),  tenant = \(tenant!)")

        monitor.on(sendCPUMetrics)
        monitor.on(sendMemMetrics)
        monitor.on(sendAARData)

        self.envInitandTopoRegister()

    }

    func sendCPUMetrics(cpu: CPUData) {

        let timeAsInterval: TimeInterval = Double(cpu.timeOfSample)/1000
        let dataDate = Date(timeIntervalSince1970: timeAsInterval)
        let dataTimeStamp = self.formatter.string(from: dataDate as Date)

        print("######################## [SwiftDataCollector] in sendCPUMetrics")

        if self.swiftDataCollectorInited {
            if ((self.cpuSampleTime == 0)||((timeAsInterval - self.cpuSampleTime) > 60)){

                self.cpuSampleTime = timeAsInterval

                let systemCPUMetrics : Dictionary<String,Any> = [
                    "timestamp": dataTimeStamp,
                    "resourceID": osResourceID,
                    "dimensions": ["name": "system"],
                    "metrics": ["system_cpuPercentUsed" : cpu.percentUsedBySystem]]

                print("########### systemCPUMetrics: \(systemCPUMetrics)")

                self.bamConfig.makeAPMRequest(perfData: systemCPUMetrics, postURL: bamConfig.metricURL)

                let appCPUMetrics : Dictionary<String,Any> = [
                    "timestamp": dataTimeStamp,
                    "resourceID": appResourceID,
                    "dimensions": ["name": self.applicationName],
                    "metrics": ["app_cpuPercentUsed" : cpu.percentUsedByApplication]]

                Log.debug("appCPUMetrics: \(appCPUMetrics)")

                self.bamConfig.makeAPMRequest(perfData: appCPUMetrics, postURL: bamConfig.metricURL)
            }
        }
    }

    func sendMemMetrics(mem: MemData) {

        let timeAsInterval: TimeInterval = Double(mem.timeOfSample)/1000
        let dataDate = Date(timeIntervalSince1970: timeAsInterval)
        let dataTimeStamp = self.formatter.string(from: dataDate as Date)

        if self.swiftDataCollectorInited {
            if ((self.memSampleTime == 0)||((timeAsInterval - self.memSampleTime) > 60)){

                self.memSampleTime = timeAsInterval

                let systemMemMetrics : Dictionary<String,Any> = [
                    "timestamp": dataTimeStamp,
                    "resourceID": osResourceID,
                    "dimensions": ["name": "system"],
                    "metrics": ["system_totalMemory" : mem.totalRAMOnSystem,
                                "system_totalMemoryUsed" : mem.totalRAMUsed,
                                "system_totalMemoryFree" : mem.totalRAMFree]
                ]

                Log.debug("systemMemMetrics: \(systemMemMetrics)")

                self.bamConfig.makeAPMRequest(perfData: systemMemMetrics, postURL: bamConfig.metricURL)

                let appMemMetrics : Dictionary<String,Any> = [
                    "timestamp": dataTimeStamp,
                    "resourceID": appResourceID,
                    "dimensions": ["name": self.applicationName],
                    "metrics": ["app_memAddressSpaceSize" : mem.applicationAddressSpaceSize,
                                "app_memPrivateSize" : mem.applicationPrivateSize,
                                "app_memUsed" : mem.applicationRAMUsed]]

                Log.debug("appMemMetrics: \(appMemMetrics)")

                self.bamConfig.makeAPMRequest(perfData: appMemMetrics, postURL: bamConfig.metricURL)
            }
        }
    }

    func sendAARData(httpData: HTTPData) {

        var processID: String = ""
        var serverName: String = ""
        var serverAddress: String = ""

        let startTimeInterval: TimeInterval = Double(httpData.timeOfRequest)/1000
        let finishTimeInterval: TimeInterval = (Double(httpData.timeOfRequest) + Double (httpData.duration))/1000
        let startTime = Date(timeIntervalSince1970: startTimeInterval)
        let startTimeStamp = self.formatter.string(from: startTime as Date)
        let finishTime = Date(timeIntervalSince1970: finishTimeInterval)
        let finishTimeStamp = self.formatter.string(from: finishTime as Date)

        if self.swiftDataCollectorInited {
            if self.envData != nil{
                processID = self.envData["pid"]!
                serverName = self.envData["environment.HOSTNAME"]!
                serverAddress = self.envData["environment.CF_INSTANCE_ADDR"]!
            }

            let aarMetrics : Dictionary<String,Any> = [
                "status": "\(httpData.statusCode!)",
                "responseTime": httpData.duration]

            let documentID: String = NSUUID().uuidString

            let aarProperties : Dictionary<String,Any> = [
                "documentType": "/AAR/MIDDLEWARE/SWIFT",
                "softwareServerType": "http://open-services.net/ns/crtv#Swift",
                "resourceID": appResourceID,
                "processID": processID,
                "diagnosticsEnabled": false,
                "serverName": serverName,
                "serverAddress": serverAddress,
                "documentVersion": "2.0",
                "startTime": startTimeStamp,
                "finishTime": finishTimeStamp,
                "documentID": documentID,
                "applicationName": self.applicationName,
                "requestName": httpData.url,
                "originID": origin,
                "tenantID": tenant]

            let aarData: Dictionary<String,Any> = [
                "metrics": aarMetrics,
                "properties": aarProperties]

            Log.debug("aarData: \(aarData)")

            self.bamConfig.makeAPMRequest(perfData: aarData, postURL: bamConfig.aarURL)
        }
    }

    func envInitandTopoRegister() -> Void {

        print("####### in envInitandTop start")

        if self.registeredResources {
            return
        }
        print("####### in envInitandTop 1")

        self.envData = self.monitor.getEnvironmentData()

        if(self.envData.isEmpty) {
            self.envData = ProcessInfo.processInfo.environment
        }
        Log.debug("envData: \(envData!)")

        let currentTime = Date()
        let utcTimeZoneStr = self.formatter.string(from: currentTime as Date)

        if let envData = self.envData["environment.VCAP_APPLICATION"], !envData.isEmpty {
            let data = self.envData["environment.VCAP_APPLICATION"]!.data(using: String.Encoding.utf8)! as Data
            self.vcapAppDictionary = try! JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions.mutableContainers) as? [String: Any]
            self.registeredResources = true
        }
        else {
            self.vcapAppDictionary = [:]
            self.vcapAppDictionary["application_id"] = bamConfig.appId
            self.vcapAppDictionary["space_id"] = bamConfig.spaceId
            self.vcapAppDictionary["application_name"] = bamConfig.appName
        }

        Log.debug("vcapAppDictionary: \(vcapAppDictionary!)")

        self.applicationName = self.bamConfig.appName

        self.swiftDataCollectorInited = true

        var swiftAppResource : Dictionary<String,Any> = [
            "uniqueId": appResourceID,
            "_status" : ["status": "normal"],
            "name": self.applicationName,
            "displayLabel": self.applicationName,
            "sourceDomain": "Bluemix",
            "entityTypes": ["SwiftApplication","application"],
            "startedTime": utcTimeZoneStr,
            "references": ["runsOn":[["to": osResourceID!]]]
          ]

        for (key, value) in self.vcapAppDictionary {
            //print(" \(key) = \(value)")
            swiftAppResource["\(key)"] = value
        }
        Log.debug("swiftAppResource: \(swiftAppResource)")

        let hostName = self.envData["environment.HOSTNAME"] ?? ""
        let version = self.envData["os.version"] ?? ""
        let osName = self.envData["os.name"] ?? ""
        let osArch = self.envData["os.arch"] ?? ""
        let osVersion: String = osName + osArch + version

        let swiftOSResource : Dictionary<String,Any> = [
            "uniqueId": osResourceID,
            "_status": ["status": "normal"],
            "displayLabel": hostName,
            "name": hostName,
            "sourceDomain": "Bluemix",
            "os.version": osVersion,
            "version": version,
            "os.name": osName,
            "os.arch": osArch,
            "startedTime": utcTimeZoneStr,
            "entityTypes": ["compute"]
        ]
        Log.debug("swiftOSResource: \(swiftOSResource)")

        let swiftDCName : String = "SwiftDC-"+self.applicationName

        let swiftProvider : Dictionary<String,Any> = [
            "uniqueId": self.origin,
            "displayLabel": swiftDCName,
            "name": swiftDCName,
            "sourceDomain": "Bluemix",
            "entityTypes": ["datacollector"],
            "startTime":utcTimeZoneStr,
            "version":"1.0",
            "monitoringLevel": "L1"
        ]
        Log.debug("swiftProvider: \(swiftProvider)")

        self.bamConfig.makeAPMRequest(perfData: swiftProvider, postURL: bamConfig.providerURL)
        self.bamConfig.makeAPMRequest(perfData: swiftOSResource, postURL: bamConfig.topoURL)
        self.bamConfig.makeAPMRequest(perfData: swiftAppResource, postURL: bamConfig.topoURL)
    }
}
