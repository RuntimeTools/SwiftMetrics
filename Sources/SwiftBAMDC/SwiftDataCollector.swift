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
    public var sm:SwiftMetrics
    
    var logLevel : LoggerMessageType = .info
    var swiftDataCollectorInited = false
    var providerRegistered = false
    var osRegistered = false
    var appRegistered = false
    var appInstanceRegistered = false
    var interfaceRegistered = false
    var envData: [String:String]!
    var vcapAppDictionary : [String: Any]!
    
    var applicationName: String = "Unknown"
    var hostName : String = "Unknown"
    var version : String = ""
    var osName : String = ""
    var osArch : String = ""
    var osVersion : String = ""
    var processID: String = "Unknown"
    var serverAddress: String = "Unknown"
    
    var formatter = DateFormatter()
    var cpuSampleTime: TimeInterval = 0
    var memSampleTime: TimeInterval = 0
    
    var appResourceID: String = ""
    var osResourceID: String = ""
    var origin: String = ""
    var tenant: String = ""
    var interfaceIDs:[String] = []
    
    
    let bamConfig = BMConfig.sharedInstance
    
    public init(swiftMetricsInstance : SwiftMetrics) throws {
        
        self.logLevel = self.bamConfig.logLevel
        HeliumLogger.use(self.logLevel)
        
        self.formatter.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'SSS'Z'"
        self.formatter.timeZone = TimeZone(abbreviation: "UTC") as TimeZone!

        self.appResourceID = self.bamConfig.appId
        self.origin = self.bamConfig.dcId
        self.tenant = self.bamConfig.tenantId
        self.osResourceID = self.bamConfig.getInstanceResourceId(resName: "osID")
        
        self.sm = swiftMetricsInstance
        self.monitor = sm.monitor()
        
        monitor.on({ (_: InitData) in
            self.envInitandTopoRegister()
        })
        _ = SwiftMetricsKitura(swiftMetricsInstance: sm)
        
        Log.debug("SwiftDataCollector init: origin = \(origin), appResourceID = \(appResourceID), osResourceID = \(osResourceID),  tenant = \(tenant)")
        
        monitor.on(sendCPUMetrics)
        monitor.on(sendMemMetrics)
        monitor.on(sendAARData)
        monitor.on(envUpdate)

    }
    
    func sendCPUMetrics(cpu: CPUData) {
        
        let timeAsInterval: TimeInterval = Double(cpu.timeOfSample)/1000
        let dataDate = Date(timeIntervalSince1970: timeAsInterval)
        let dataTimeStamp = self.formatter.string(from: dataDate as Date)
        
        if self.swiftDataCollectorInited {
            if ((self.cpuSampleTime == 0)||((timeAsInterval - self.cpuSampleTime) > 60)){
                
                self.cpuSampleTime = timeAsInterval
                
                let systemCPUMetrics : Dictionary<String,Any> = [
                    "timestamp": dataTimeStamp,
                    "resourceID": osResourceID,
                    "dimensions": ["name": "system"],
                    "metrics": ["system_cpuPercentUsed" : cpu.percentUsedBySystem]]
                
                Log.debug("systemCPUMetrics: \(systemCPUMetrics)")
                
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
        
        let startTimeInterval: TimeInterval = Double(httpData.timeOfRequest)/1000
        let finishTimeInterval: TimeInterval = (Double(httpData.timeOfRequest) + Double (httpData.duration))/1000
        let startTime = Date(timeIntervalSince1970: startTimeInterval)
        let startTimeStamp = self.formatter.string(from: startTime as Date)
        let finishTime = Date(timeIntervalSince1970: finishTimeInterval)
        let finishTimeStamp = self.formatter.string(from: finishTime as Date)
        
        if self.swiftDataCollectorInited {
            
            let aarMetrics : Dictionary<String,Any> = [
                "status": "\(String(describing: httpData.statusCode))",
                "responseTime": httpData.duration]
            
            let documentID: String = NSUUID().uuidString
            
            let aarProperties : Dictionary<String,Any> = [
                "documentType": "/AAR/MIDDLEWARE/SWIFT",
                "softwareServerType": "http://open-services.net/ns/crtv#Swift",
                "resourceID": self.appResourceID,
                "diagnosticsEnabled": false,
                "documentVersion": "2.0",
                "startTime": startTimeStamp,
                "finishTime": finishTimeStamp,
                "documentID": documentID,
                "requestName": httpData.url,
                "serverName": self.hostName,
                "processID": self.processID,
                "serverAddress": self.serverAddress,
                "applicationName": self.applicationName,
                "originID": self.origin,
                "tenantID": self.tenant]
            
            /*if self.hostName != "Unknown" {
             aarProperties ["serverName"] = self.hostName
             }
             
             if self.processID != "Unknown" {
             aarProperties ["processID"] = self.processID
             }
             
             if self.serverAddress != "Unknown" {
             aarProperties ["serverAddress"] = self.serverAddress
             }
             
             if self.applicationName != "Unknown" {
             aarProperties ["applicationName"] = self.applicationName
             }*/
            
            let aarData: Dictionary<String,Any> = [
                "metrics": aarMetrics,
                "properties": aarProperties]
            
            Log.debug("aarData: \(aarData)")
            
            self.bamConfig.makeAPMRequest(perfData: aarData, postURL: bamConfig.aarURL)
        }
    }
    
    func envInitandTopoRegister() -> Void {
        
        Log.debug("envInitandTopoRegister() enter")
        
        if (!self.providerRegistered || !self.osRegistered || !self.appRegistered || !self.interfaceRegistered || !self.appInstanceRegistered) {
            
            self.envData = self.monitor.getEnvironmentData()
            
            if self.envData != nil {
                
                Log.debug("Before envData:")
                
                Log.debug("envData: \(self.envData)")
                
                for (param, value) in self.envData {
                    switch param {
                    case "environment.VCAP_APPLICATION":
                        if !value.isEmpty{
                            Log.debug("environment.VCAP_APPLICATION: \(value)")
                            
                            let data = value.data(using: String.Encoding.utf8)! as Data
                            self.vcapAppDictionary = try! JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions.mutableContainers) as? [String: Any]
                            if self.vcapAppDictionary != nil {
                                self.applicationName = self.vcapAppDictionary["application_name"] as! String
                            }
                            self.swiftDataCollectorInited = true
                            
                            Log.debug("vcapAppDictionary: \(vcapAppDictionary)")
                        }
                    case "environment.HOSTNAME":
                        self.hostName = value
                        Log.debug("hostName: \(value)")
                    case "os.version":
                        self.osVersion = value
                        Log.debug("version: \(value)")
                    case "os.name":
                        self.osName = value
                        Log.debug("os.name: \(value)")
                    case "os.arc":
                        self.osArch = value
                        Log.debug("os.arc: \(value)")
                    case "pid":
                        self.processID = value
                        Log.debug("processID: \(value)")
                    case "environment.CF_INSTANCE_ADDR":
                        self.serverAddress = value
                        Log.debug("serverAddress: \(value)")
                    default:
                        continue
                    }
                }
                
                self.version = self.osName + self.osArch + self.osVersion
                
                if !self.providerRegistered {
                    registerProvider()
                }
                if !self.osRegistered {
                    registerOS()
                }
                if !self.appRegistered {
                    registerApplication()
                }
                if !self.interfaceRegistered {
                    registerInterfaces()
                }
                if !self.appInstanceRegistered {
                    registerApplicationInstance()
                }
                
            }else{
                Log.info("The environment data is not available yet, initialization failed")
            }
        }
    }
    
    func registerProvider() -> Void {
        
        let currentTime = Date()
        let utcTimeZoneStr = self.formatter.string(from: currentTime as Date)
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
        if (self.applicationName != "Unknown") {
            self.providerRegistered = true
            Log.debug("providerRegistered: \(self.providerRegistered)")
        }
    }
    
    func registerOS() -> Void {
        
        let currentTime = Date()
        let utcTimeZoneStr = self.formatter.string(from: currentTime as Date)
        
        let swiftOSResource : Dictionary<String,Any> = [
            "uniqueId": self.osResourceID,
            "displayLabel": self.hostName,
            "name": self.hostName,
            "sourceDomain": "Bluemix",
            "os.version": self.osVersion,
            "version": self.version,
            "os.name": self.osName,
            "os.arch": self.osArch,
            "startedTime": utcTimeZoneStr,
            "entityTypes": ["compute"]
        ]
        Log.debug("swiftOSResource: \(swiftOSResource)")
        
        self.bamConfig.makeAPMRequest(perfData: swiftOSResource, postURL: bamConfig.topoURL)
        if (self.version != "") {
            self.osRegistered = true
            Log.debug("osRegistered: \(self.osRegistered)")
        }
    }
    
    func registerInterfaces() -> Void {
        
        let currentTime = Date()
        let utcTimeZoneStr = self.formatter.string(from: currentTime as Date)
        var port = ""
        
        if let portNumber = self.vcapAppDictionary ["port"] {
            port = "\(portNumber)"
            Log.debug("port: \(port)")
        }
        
        if let applicationUris = self.vcapAppDictionary ["application_uris"] {
            
            if let applicationUrisArray = applicationUris as? Array<String>{
 
                for uri in applicationUrisArray {
                    let interfaceID = self.bamConfig.getResourceId(resName: uri)
                    self.interfaceIDs.append(interfaceID)
                    let swiftInterfaceResource : Dictionary<String,Any> = [
                        "uniqueId": interfaceID,
                        "name": uri,
                        "displayLabel": uri,
                        "sourceDomain": "Bluemix",
                        "uri": uri,
                        "port": port,
                        "entityTypes": ["interface"],
                        "startedTime": utcTimeZoneStr,
                        "_references": [["_fromUniqueId": self.appResourceID, "_edgeType": "has"]]
                    ]
                    
                    Log.debug("swiftInterfaceResource: \(swiftInterfaceResource)")
                    
                    self.bamConfig.makeAPMRequest(perfData: swiftInterfaceResource, postURL: bamConfig.topoURL)
                    
                    if (uri != "") {
                        self.interfaceRegistered = true
                        Log.debug("interfaceRegistered: \(self.interfaceRegistered)")
                    }
                }
            }
        }
        
    }

    
    func registerApplication() -> Void {
        
        let currentTime = Date()
        let utcTimeZoneStr = self.formatter.string(from: currentTime as Date)
        
        var swiftAppResource : Dictionary<String,Any> = [
            "uniqueId": self.appResourceID,
            "name": self.applicationName,
            "displayLabel": self.applicationName,
            "sourceDomain": "Bluemix",
            "entityTypes": ["swiftApplication","application"],
            "startedTime": utcTimeZoneStr
        ]
        
        if self.vcapAppDictionary != nil {
            for (key, value) in self.vcapAppDictionary {
                if (key != "application_name" && key != "application_uris" && key != "instance_id" && key != "instance_index" && key != "uris" && key != "port") {
                swiftAppResource["\(key)"] = value
                }
            }
        }
        
        Log.debug("swiftAppResource: \(swiftAppResource)")
        
        self.bamConfig.makeAPMRequest(perfData: swiftAppResource, postURL: bamConfig.topoURL)
        
        if (self.applicationName != "Unknown") {
            self.appRegistered = true
            Log.debug("appRegistered: \(self.appRegistered)")
        }
    }
    
    
    func registerApplicationInstance() -> Void {
        
        let currentTime = Date()
        let utcTimeZoneStr = self.formatter.string(from: currentTime as Date)
        let appInstanceResID = self.bamConfig.getInstanceResourceId(resName: self.applicationName)
        
        var appInstanceIndex = ""
        var instanceID = ""
        var relationships: [[String:String]] = [[:]]
        
        if let instanceIndex = self.vcapAppDictionary ["instance_index"] {
            appInstanceIndex = "\(instanceIndex)"
            Log.debug("instanceIndex: \(instanceIndex)")
        }
        if let instID = self.vcapAppDictionary ["instance_id"] {
            if let instIDStr = instID as? String {
                instanceID = instIDStr
            }
        }
        
        var swiftAppInstanceResource : Dictionary<String,Any> = [
            "uniqueId": appInstanceResID,
            "name": self.applicationName+":"+appInstanceIndex,
            "displayLabel": self.applicationName+":"+appInstanceIndex,
            "sourceDomain": "Bluemix",
            "instance_index": appInstanceIndex,
             "instance_id": instanceID,
            "entityTypes": ["swiftApplicationInstance","applicationInstance"],
            "startedTime": utcTimeZoneStr
        ]
        
        relationships = [["_toUniqueId": self.appResourceID, "_edgeType": "realizes"]]
        
        for interfaceID in interfaceIDs {
            
            let relationShip = ["_toUniqueId": interfaceID, "_edgeType": "implements"]

            relationships.append(relationShip)
        }
        
        swiftAppInstanceResource["_references"] = relationships
        
        Log.debug("swiftAppInstanceResource: \(swiftAppInstanceResource)")
        
        self.bamConfig.makeAPMRequest(perfData: swiftAppInstanceResource, postURL: bamConfig.topoURL)
        
        if (appInstanceIndex != "") {
            self.appInstanceRegistered = true
            Log.debug("appInstanceRegistered: \(self.appInstanceRegistered)")
        }
    }
    
    func envUpdate(env: EnvData) {
        
        self.envInitandTopoRegister()
    }
    
}

/* Sample of VCAP_APPLICATION:
environment.VCAP_APPLICATION: 
 {
 "application_id": "b922eb72-1d1e-4fed-bdbd-1838c6fecbe1",
 "application_name": "Swiftc-DC",
 "application_uris": [
 "Swiftc-DC.stage1.mybluemix.net"
 ],
 "application_version": "eb8e9357-c4bf-4433-8d4b-fe2d2628fc6a",
 "host": "0.0.0.0",
 "instance_id": "08bb0426-0d20-400e-74a9-6d1889c90c21",
 "instance_index": 0,
 "limits": {
 "disk": 1024,
 "fds": 16384,
 "mem": 256
 },
 "name": "Swiftc-DC",
 "port": 8080,
 "space_id": "739f4a7e-acae-441b-bd29-c38bfb7cf3f0",
 "space_name": "dev",
 "uris": [
 "Swiftc-DC.stage1.mybluemix.net"
 ],
 "users": null,
 "version": "eb8e9357-c4bf-4433-8d4b-fe2d2628fc6a"
 }
End of VCAP_APPLICATION sample*/
