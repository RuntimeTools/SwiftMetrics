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

public class SwiftDataCollectorInit {
    
    public var monitor:SwiftMonitor
    var resRegistered : [String: Bool] = [
        "providerRegistered": false, "osRegistered": false,
        "appRegistered": false, "appInstanceRegistered": false,
        "interfaceRegistered": false]
    
    var envData: [String:String]!
    var vcapAppDictionary : [String: Any]!
    
    var interfaceIDs:[String] = []
    
    let bamConfig = BMConfig.sharedInstance
    
    init(swiftMetricsInstance : SwiftMetrics) throws {
        
        var sm:SwiftMetrics
        
        var logLevel : LoggerMessageType = .info
        
        logLevel = self.bamConfig.logLevel
        HeliumLogger.use(logLevel)
        
        sm = swiftMetricsInstance
        self.monitor = sm.monitor()
        
        monitor.on({ (_: InitData) in
            self.envInitandTopoRegister()
        })
        _ = SwiftMetricsKitura(swiftMetricsInstance: sm)
        
        monitor.on(envUpdate)
    }
    
    func envInitandTopoRegister() -> Void {
        
        if (self.resRegistered["providerRegistered"]! && self.resRegistered["osRegistered"]! && self.resRegistered["appRegistered"]! && self.resRegistered["interfaceRegistered"]! && self.resRegistered["appInstanceRegistered"]!) {
            return
        }
        
        self.envData = self.monitor.getEnvironmentData()
        
        if self.envData != nil {
            for (param, value) in self.envData {
                switch param {
                case "environment.VCAP_APPLICATION":
                    Log.debug("environment.VCAP_APPLICATION: \(value)")
                    
                    let data = value.data(using: String.Encoding.utf8)! as Data
                    self.vcapAppDictionary = try! JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions.mutableContainers) as? [String: Any]
                default:
                    continue
                }
            }
        }
        else{
            Log.info("The environment data is not available yet, initialization failed")
        }
        
        if !self.resRegistered["providerRegistered"]! {
            registerProvider()
        }
        if !self.resRegistered["osRegistered"]! {
            registerOS()
        }
        if !self.resRegistered["appRegistered"]! {
            registerApplication()
        }
        if !self.resRegistered["interfaceRegistered"]! {
            registerInterfaces()
        }
        if !self.resRegistered["appInstanceRegistered"]! {
            registerApplicationInstance()
        }
    }
    
    func registerProvider() -> Void {
        
        let currentTime = Date()
        let utcTimeZoneStr = getISOTimeStamp(time: currentTime as Date)
        let swiftDCName : String = "SwiftDC-"+self.bamConfig.appName
        
        let swiftProvider : Dictionary<String,Any> = [
            "uniqueId": self.bamConfig.dcId, "displayLabel": swiftDCName,
            "name": swiftDCName, "sourceDomain": "Bluemix",
            "entityTypes": ["datacollector"], "startTime":utcTimeZoneStr,
            "version":"1.0", "monitoringLevel": "L1"]
        Log.debug("swiftProvider: \(swiftProvider)")
        
        self.bamConfig.makeAPMRequest(perfData: swiftProvider, postURL: bamConfig.providerURL)
        if (self.bamConfig.appName != "") {
            self.resRegistered["providerRegistered"] = true
            Log.debug("providerRegistered: \(String(describing: self.resRegistered["providerRegistered"]))")
        }
    }
    
    func registerOS() -> Void {
        
        let currentTime = Date()
        let utcTimeZoneStr = getISOTimeStamp(time: currentTime as Date)
        
        var hostName : String = "Unknown"
        var version : String = ""
        var osName : String = ""
        var osArch : String = ""
        var osVersion : String = ""
        
        if self.envData != nil {
            for (param, value) in self.envData {
                switch param {
                case "environment.HOSTNAME":
                    hostName = value
                //Log.debug("hostName: \(value)")
                case "os.version":
                    osVersion = value
                //Log.debug("version: \(value)")
                case "os.name":
                    osName = value
                //Log.debug("os.name: \(value)")
                case "os.arc":
                    osArch = value
                //Log.debug("os.arc: \(value)")
                default:
                    continue
                }
            }
        }
        
        version = osName + osArch + osVersion
        
        let swiftOSResource : Dictionary<String,Any> = [
            "uniqueId": self.bamConfig.getInstanceResourceId(resName: "osID"),
            "displayLabel": hostName, "name": hostName, "sourceDomain": "Bluemix", "os.version": osVersion,
            "version": version, "os.name": osName, "os.arch": osArch, "startedTime": utcTimeZoneStr,
            "entityTypes": ["compute"]]
        Log.debug("swiftOSResource: \(swiftOSResource)")
        
        self.bamConfig.makeAPMRequest(perfData: swiftOSResource, postURL: bamConfig.topoURL)
        if (version != "") {
            self.resRegistered["osRegistered"] = true
            Log.debug("osRegistered: \(String(describing: self.resRegistered["osRegistered"]))")
        }
    }
    
    func registerInterfaces() -> Void {
        
        let currentTime = Date()
        let utcTimeZoneStr = getISOTimeStamp(time: currentTime as Date)
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
                        "uniqueId": interfaceID, "name": uri, "displayLabel": uri, "sourceDomain": "Bluemix",
                        "uri": uri, "port": port, "entityTypes": ["interface"], "startedTime": utcTimeZoneStr,
                        "_references": [["_fromUniqueId": self.bamConfig.appId, "_edgeType": "has"]]]
                    
                    Log.debug("swiftInterfaceResource: \(swiftInterfaceResource)")
                    
                    self.bamConfig.makeAPMRequest(perfData: swiftInterfaceResource, postURL: bamConfig.topoURL)
                    
                    if (uri != "") {
                        self.resRegistered["interfaceRegistered"] = true
                        Log.debug("interfaceRegistered: \(String(describing: self.resRegistered["interfaceRegistered"]))")
                    }
                }
            }
        }
        
    }
    
    func registerApplication() -> Void {
        
        let currentTime = Date()
        let utcTimeZoneStr = getISOTimeStamp(time: currentTime as Date)
        
        var swiftAppResource : Dictionary<String,Any> = [
            "uniqueId": self.bamConfig.appId, "name": self.bamConfig.appName,
            "displayLabel": self.bamConfig.appName, "sourceDomain": "Bluemix",
            "entityTypes": ["swiftApplication","application"], "startedTime": utcTimeZoneStr]
        
        if self.vcapAppDictionary != nil {
            for (key, value) in self.vcapAppDictionary {
                if (key != "application_name" && key != "application_uris" && key != "instance_id" && key != "instance_index" && key != "uris" && key != "port") {
                    swiftAppResource["\(key)"] = value
                }
            }
        }
        
        Log.debug("swiftAppResource: \(swiftAppResource)")
        
        self.bamConfig.makeAPMRequest(perfData: swiftAppResource, postURL: bamConfig.topoURL)
        
        if (self.bamConfig.appName != "") {
            self.resRegistered["appRegistered"] = true
            Log.debug("appRegistered: \(String(describing: self.resRegistered["appRegistered"]))")
        }
    }
    
    
    func registerApplicationInstance() -> Void {
        
        let currentTime = Date()
        let utcTimeZoneStr = getISOTimeStamp(time: currentTime as Date)
        let applicationName = self.bamConfig.appName
        let appInstanceResID = self.bamConfig.getInstanceResourceId(resName: applicationName)
        
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
            "uniqueId": appInstanceResID, "name": applicationName+":"+appInstanceIndex,
            "displayLabel": applicationName+":"+appInstanceIndex,
            "sourceDomain": "Bluemix","instance_index": appInstanceIndex,
            "instance_id": instanceID, "entityTypes": ["swiftApplicationInstance","applicationInstance"],
            "startedTime": utcTimeZoneStr]
        
        relationships = [["_toUniqueId": self.bamConfig.appId, "_edgeType": "realizes"]]
        
        for interfaceID in interfaceIDs {
            
            let relationShip = ["_toUniqueId": interfaceID, "_edgeType": "implements"]
            relationships.append(relationShip)
        }
        
        swiftAppInstanceResource["_references"] = relationships
        
        Log.debug("swiftAppInstanceResource: \(swiftAppInstanceResource)")
        
        self.bamConfig.makeAPMRequest(perfData: swiftAppInstanceResource, postURL: bamConfig.topoURL)
        
        if (appInstanceIndex != "") {
            self.resRegistered["appInstanceRegistered"] = true
            Log.debug("appInstanceRegistered: \(String(describing: self.resRegistered["appInstanceRegistered"]))")
        }
    }
    
    func envUpdate(env: EnvData) {
        
        self.envInitandTopoRegister()
    }

}


public class SwiftDataCollector : SwiftDataCollectorInit {
    
    var sampleTime : [String: TimeInterval] = [
        "cpuSampleTime": 0,
        "memSampleTime": 0]
    
    override init(swiftMetricsInstance : SwiftMetrics) throws {
      
        try super.init(swiftMetricsInstance : swiftMetricsInstance)
        
        self.monitor.on(sendCPUMetrics)
        self.monitor.on(sendMemMetrics)
        self.monitor.on(sendAARData)

    }
    
    func sendCPUMetrics(cpu: CPUData) {
        
        let timeAsInterval: TimeInterval = Double(cpu.timeOfSample)/1000
        let dataDate = Date(timeIntervalSince1970: timeAsInterval)
        let dataTimeStamp = getISOTimeStamp(time: dataDate as Date)
        
        if self.vcapAppDictionary != nil {
            if ((self.sampleTime["cpuSampleTime"]! == 0)||((timeAsInterval - self.sampleTime["cpuSampleTime"]!) > 60)){
                
                self.sampleTime["cpuSampleTime"] = timeAsInterval
                
                let systemCPUMetrics : Dictionary<String,Any> = [
                    "timestamp": dataTimeStamp,
                    "resourceID": self.bamConfig.getInstanceResourceId(resName: "osID"),
                    "dimensions": ["name": "system"],
                    "metrics": ["system_cpuPercentUsed" : cpu.percentUsedBySystem]]
                
                Log.debug("systemCPUMetrics: \(systemCPUMetrics)")
                
                self.bamConfig.makeAPMRequest(perfData: systemCPUMetrics, postURL: bamConfig.metricURL)
                
                let appCPUMetrics : Dictionary<String,Any> = [
                    "timestamp": dataTimeStamp,
                    "resourceID": self.bamConfig.appId,
                    "dimensions": ["name": self.bamConfig.appName],
                    "metrics": ["app_cpuPercentUsed" : cpu.percentUsedByApplication]]
                
                Log.debug("appCPUMetrics: \(appCPUMetrics)")
                
                self.bamConfig.makeAPMRequest(perfData: appCPUMetrics, postURL: bamConfig.metricURL)
            }
        }
    }
    
    func sendMemMetrics(mem: MemData) {
        
        let timeAsInterval: TimeInterval = Double(mem.timeOfSample)/1000
        let dataDate = Date(timeIntervalSince1970: timeAsInterval)
        let dataTimeStamp = getISOTimeStamp(time: dataDate as Date)
        
        if self.vcapAppDictionary != nil {
            if ((self.sampleTime["memSampleTime"]! == 0)||((timeAsInterval - self.sampleTime["memSampleTime"]!) > 60)){
                
                self.sampleTime["memSampleTime"] = timeAsInterval
                
                let systemMemMetrics : Dictionary<String,Any> = [
                    "timestamp": dataTimeStamp,
                    "resourceID": self.bamConfig.getInstanceResourceId(resName: "osID"),
                    "dimensions": ["name": "system"],
                    "metrics": ["system_totalMemory" : mem.totalRAMOnSystem,
                                "system_totalMemoryUsed" : mem.totalRAMUsed,
                                "system_totalMemoryFree" : mem.totalRAMFree]
                ]
                
                Log.debug("systemMemMetrics: \(systemMemMetrics)")
                
                self.bamConfig.makeAPMRequest(perfData: systemMemMetrics, postURL: bamConfig.metricURL)
                
                let appMemMetrics : Dictionary<String,Any> = [
                    "timestamp": dataTimeStamp,
                    "resourceID": self.bamConfig.appId,
                    "dimensions": ["name": self.bamConfig.appName],
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
        let startTimeStamp = getISOTimeStamp(time: startTime as Date)
        let finishTime = Date(timeIntervalSince1970: finishTimeInterval)
        let finishTimeStamp = getISOTimeStamp(time: finishTime as Date)
        
        var hostName : String = "Unknown"
        var processID: String = "Unknown"
        var serverAddress: String = "Unknown"
        
        if self.envData != nil {
            for (param, value) in self.envData {
                switch param {
                case "environment.HOSTNAME":
                    hostName = value
                    Log.debug("hostName: \(value)")
                case "pid":
                    processID = value
                    Log.debug("processID: \(value)")
                case "environment.CF_INSTANCE_ADDR":
                    serverAddress = value
                    Log.debug("serverAddress: \(value)")
                default:
                    continue
                }
            }
        }
        
        if self.vcapAppDictionary != nil {
            
            let aarMetrics : Dictionary<String,Any> = [
                "status": "\(String(describing: httpData.statusCode))",
                "responseTime": httpData.duration]
            
            let documentID: String = NSUUID().uuidString
            
            let aarProperties : Dictionary<String,Any> = [
                "documentType": "/AAR/MIDDLEWARE/SWIFT",
                "softwareServerType": "http://open-services.net/ns/crtv#Swift",
                "resourceID": self.bamConfig.appId, "diagnosticsEnabled": false,
                "documentVersion": "2.0", "startTime": startTimeStamp, "finishTime": finishTimeStamp,
                "documentID": documentID, "requestName": httpData.url, "serverName": hostName,
                "processID": processID, "serverAddress": serverAddress, "applicationName": self.bamConfig.appName,
                "originID": self.bamConfig.dcId, "tenantID": self.bamConfig.tenantId]
            
            let aarData: Dictionary<String,Any> = ["metrics": aarMetrics,"properties": aarProperties]
            
            Log.debug("aarData: \(aarData)")
            
            self.bamConfig.makeAPMRequest(perfData: aarData, postURL: bamConfig.aarURL)
        }
    }
    
}

public func getISOTimeStamp(time : Date) -> String {
    
    let formatter = DateFormatter()
    
    formatter.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'SSS'Z'"
    formatter.timeZone = TimeZone(abbreviation: "UTC") as TimeZone!
    
    return formatter.string(from: time)
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
