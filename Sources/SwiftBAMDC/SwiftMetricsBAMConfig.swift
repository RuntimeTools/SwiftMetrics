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

/**
 * This class helps in initialization of BAM Configuration
 **/

//import Configuration
import CloudFoundryEnv
import LoggerAPI
import Cryptor
import Foundation
import Dispatch
import SwiftyRequest
import Configuration

/*
 #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
 import CommonCrypto
 #elseif os(Linux)
 import OpenSSL
 #endif
 */

////////////// Global Variables

public var processLocalEnv : [String:Any] = ProcessInfo.processInfo.environment

let HTTP_POST: String = "POST"
let HTTP_GET: String = "GET"
let SB_PATH: String = "/1.0/credentials/app/"
let INGRESS_PATH: String = "/1.0/data"

/*
 This Class represents basic BAM Configuration interface. Each environments can subclass this class for
 adaption to their environment

 */

public class IBAMConfigIDs {

    public var appId    : String
    public var appName  : String
    public var tenantId : String
    public var dcId     : String

    public var logLevel : LoggerMessageType = .info

    init() {

        let logLevelString = getEnvironmentVal(name: "IBAM_LOG_LEVEL", defVal: ".info")

        self.appId        = getEnvironmentVal(name: "IBAM_APPLICATION_ID")
        self.appName      = getEnvironmentVal(name: "IBAM_APPLICATION_NAME")
        self.tenantId     = getEnvironmentVal(name: "X-TenantId")
        self.dcId         = UUID().uuidString.lowercased()

        logLevel = stringToLoggerMessageType(logLevelString: logLevelString)
        
        self.getIDsFromCFEnv()
        self.getIDsFromLocalEnv()
    }

    public func getIDsFromCFEnv () {

        var spaceId : String = ""
        var instanceId : String = ""
        var instanceIndex : String = ""

        var configManager: ConfigurationManager?

        configManager = ConfigurationManager()
        configManager?.load(.environmentVariables)

        if let app = configManager?.getApp() {

            Log.info("[SwiftMetricsBAMConfig] Retrieving application info from CloudFoundryEnv \(app)")

            if self.appId.isEmpty {
                self.appId = app.id
            }
            if spaceId.isEmpty {
                spaceId = app.spaceId
            }
            if self.appName.isEmpty {
                self.appName = app.name
            }
            if instanceId.isEmpty {
                instanceId = app.instanceId
            }
            if instanceIndex.isEmpty {
                instanceIndex = "\(app.instanceIndex)"
            }
        }

        if self.tenantId.isEmpty {
            self.tenantId = spaceId
        }

        if !self.appId.isEmpty {
            self.dcId = TokenUtil.md5(resName: self.appId + instanceIndex)
        }

        Log.info("[SwiftMetricsBAMConfig] getIDsFromCFEnv default init, tenantId: \(self.tenantId) AppName: \(self.appName) InstanceId: \(instanceId) InstanceIndex: \(instanceIndex) DCID: \(dcId)")
    }

    public func getIDsFromLocalEnv () {

        var spaceId : String = ""
        var instanceId : String = ""
        var instanceIndex : String = ""

        let processName = ProcessInfo.processInfo.processName

        if self.appId.isEmpty {
            self.appId = TokenUtil.md5(resName: processName)
        }
        if spaceId.isEmpty {
            spaceId = self.appId
        }
        if self.appName.isEmpty {
            self.appName = processName
        }
        if instanceId.isEmpty {
            instanceId = self.appId
        }
        if instanceIndex.isEmpty {
            instanceIndex = "0"
        }

        if self.tenantId.isEmpty {
            self.tenantId = spaceId
        }

        if !self.appId.isEmpty {
            self.dcId = TokenUtil.md5(resName: self.appId + instanceIndex)
        }

        Log.info("[SwiftMetricsBAMConfig] getIDsFromLocalEnv default init, tenantId: \(self.tenantId) AppName: \(self.appName) InstanceId: \(instanceId) InstanceIndex: \(instanceIndex) DCID: \(dcId)")
    }

    public func stringToLoggerMessageType(logLevelString: String) -> LoggerMessageType {

        switch logLevelString {
        case ".entry":
            return .entry
        case ".exit":
            return .exit
        case ".debug":
            return .debug
        case ".verbose":
            return .verbose
        case ".info":
            return .info
        case ".warning":
            return .warning
        case ".error":
            return .error
        default:
            return .info
        }
    }
}

public class IBAMConfig : IBAMConfigIDs {

    public var topoURL: String = ""
    public var providerURL: String = ""
    public var metricURL: String = ""
    public var aarURL: String = ""
    public var adrURL: String = ""

    // by default queue is serial attributes: .serial
    fileprivate let queue = DispatchQueue(label: "com.ibm.bam", qos: .background, target: nil)

    public var ingressHeaders : [String: String] = [
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "SwiftDC"
    ]

    fileprivate var backendReady: Bool = false

    //This will get overwritten by VCAP_SERVICES and VCAP_APPLICATION below.
    //  These env should take precedence so even in Bluemix they can be
    //  use as overrides to VCAP_* not the other way around
    override init() {

        super.init()
        populateLocalEnvironment() // must be the first line

    }

    private func populateLocalEnvironment() {

        let debugEnvStr = getEnvironmentVal(name: "IBAM_DEBUG_ENV")

        if !debugEnvStr.isEmpty {
            Log.info("[SwiftMetricsBAMConfig] DEBUG environment is set: \(debugEnvStr)")
        }

        if let envDic = stringToJSON(text: debugEnvStr) {
            for (key, val) in envDic {
                processLocalEnv[key] = val
            }
        }
        Log.info("[SwiftMetricsBAMConfig] Environment: \(processLocalEnv)")
    }
}

public class BMConfig : IBAMConfig {

    // service broker url & token if any
    public var sbURL   : String
    public var sbToken : String

    // BAM server properties required by users
    public var ingressURL: String
    public var ingressToken: String

    fileprivate var maxRetryLimit : Int = 3
    fileprivate var retryCount = 0

    // lazily initialized
    static let sharedInstance: BMConfig = {
        let instance = BMConfig()
        // any set up code goes here
        return instance
    }()

    private override init() {

        sbURL        = getEnvironmentVal(name: "IBAM_SB_URL")
        sbToken      = getEnvironmentVal(name: "IBAM_SB_TOKEN")

        ingressURL   = getEnvironmentVal(name: "IBAM_INGRESS_URL")
        ingressToken = getEnvironmentVal(name: "IBAM_TOKEN")

        if let limit = Int(getEnvironmentVal(name: "IBAM_MAX_RETRY_LIMIT", defVal: "3")) {
            self.maxRetryLimit = limit
        }

        super.init()
        cloudFoundryBasedInitialization()
    }

    // Initialize environment based on CloudFoundry Object
    private func cloudFoundryBasedInitialization() {
        var configManager: ConfigurationManager?
        var serviceName: String

        serviceName  = getEnvironmentVal(name: "IBAM_SVC_NAME", defVal: "AvailabilityMonitoring")

        configManager = ConfigurationManager()
        configManager?.load(.environmentVariables)

        Log.info("[SwiftMetricsBAMConfig] ConfigManager: \(String(describing: configManager))")

        // VCAP_SERVICES initialization
        // Service name can be changed by the user and hence name based query is NOT used
        // Use service label instead

        var servCreds : [String:Any] = [:]

        //if let vcapServices = self.cfAppEnv?.getServices() {
        if let vcapServices = configManager?.getServices() {
            Log.info("[SwiftMetricsBAMConfig] Retrieving vcapservice info from CloudFoundryEnv \(vcapServices)")

            for (serName, service) in vcapServices {

                if(service.label.range(of: serviceName) != nil) {
                    if let creds = service.credentials {
                        servCreds = creds
                        Log.info("[SwiftMetricsBAMConfig] cloudFoundryBasedInitialization: Service credentials successfully obtained for \(serName) Creds: \(servCreds)")
                        break
                    }
                }
            }
        }

        Log.info("[SwiftMetricsBAMConfig] cloudFoundryBasedInitialization: \(servCreds)")

        var tmpSBToken: String = self.sbToken

        if tmpSBToken.isEmpty, let sbt = servCreds["token"] as? String {
            tmpSBToken = sbt
        }

        if tmpSBToken.count > 0 {
            self.sbToken = TokenUtil.unobfuscate(key: appId, value: tmpSBToken)
            Log.info("[SwiftMetricsBAMConfig] SB token set successfully \(self.sbToken)")
        }

        if self.sbURL.isEmpty, let surl = servCreds["cred_url"] as? String {
            self.sbURL = surl + SB_PATH + self.appId
            Log.info("[SwiftMetricsBAMConfig] SB URL set successfully \(self.sbURL)")
        }

        Log.info("[SwiftMetricsBAMConfig] BMConfig default init, SBURL: \(self.sbURL) SBToken: \(tmpSBToken) ServCreds: \(servCreds) tenantId: \(self.tenantId) AppName: \(self.appName) DCID: \(dcId)")

        self.refreshBAMConfigTask()
    }

    /*
     SB Query:
     curl -H 'Accept: application/json' -H 'X-TenantId: a7d34a39-0cee-48cd-bf46-d732a1e15775' -H 'Authorization: bamtoken gdlc49a4a2sj7ns87i9nj2e7saphds7fonohiijvpn9osgn5q2qoturtlmrcdgat' -H 'User-Agent: SwiftDC' 'https://perfbroker-apd.stage1.ng.bluemix.net/1.0/credentials/app/55486f24-cd6e-440b-9589-3e2e5000095e'

     Curl response:

     {"backend_url":"https:\/\/hcdemo.test.perfmgmt.ibm.com","token":"gdlc49a4a2sj7ns87i9nj2e7saphds7fonohiijvpn9osgn5q2qoturtlmrcdgat"}
     */

    public func refreshBAMConfig() {
        if(retryCount < maxRetryLimit) {

            Log.info("[SwiftMetricsBAMConfig] Retrying to get BAM configuration \(retryCount)")

            self.queue.asyncAfter(deadline: .now() + .milliseconds(5000 * retryCount), execute: {

                self.refreshBAMConfigTask()
            })

            retryCount += 1
        }
    }

    func refreshBAMConfigTask() {

        Log.debug("[SwiftMetricsBAMConfig] Refreshing BAM Configuration:  \(sbURL)")

        if(self.backendReady) {
            return
        }

        if self.ingressURL.count > 0 {
            refreshBAMConfigWithBasicAuth()
            return
        }

        //this does not appear to be threadsafe
        if !(self.sbURL.count > 0) {
            Log.error("[SwiftMetricsBAMConfig] No AvailabilityMonitoring Service connected and no IBAM_INGRESS_URL/IBAM_TOKEN set.")
            return
        }

            /*"cred_url": "https://perfbroker-apd.stage1.ng.bluemix.net/1.0/credentials/app/55486f24-cd6e-440b-9589-3e2e5000095e"
             */

            let auth = "bamtoken " + self.sbToken
            let hdrs = ["Accept": "application/json", "X-TenantId": self.tenantId, "Authorization": auth, "User-Agent": "SwiftDC"]

            Log.info("[SwiftMetricsBAMConfig] BAM credentials request initiated, URL: \(sbURL) BAM headers: \(hdrs) ")

            BMConfig.makeKituraHttpRequest(apmData: [:], urlString: self.sbURL, reqType: HTTP_GET, headers: hdrs, taskCallback: {
                (passed, statusCode, response) in

                if(passed) {
                    if let config = response as? [String:Any] {
                        if let bu = config["backend_url"] as? String {

                            Log.debug("[SwiftMetricsBAMConfig] Backend url obtained: \(bu)")
                            let newString = bu.replacingOccurrences(of: " ", with: "", options: .literal, range: nil)

                            Log.debug("[SwiftMetricsBAMConfig] Backend url refined: \(newString)")

                            self.ingressURL = newString
                        }

                        if let it = config["token"] as? String {
                            self.ingressToken = it
                        }

                        self.getBAMURLs(authorization: "bamtoken ")

                        self.backendReady  = true

                        // TODO: comment out token
                        Log.debug("[SwiftMetricsBAMConfig] BAM initialization successful, backend ready to accept requests, URL: \(self.ingressURL) BAM token: \(self.ingressToken)")

                        // TODO: don't log token in headers
                        Log.debug("[SwiftMetricsBAMConfig] BAM backend Urls: \(self.metricURL) Header: \(self.ingressHeaders)")
                    }
                }
                else {
                    Log.warning("[SwiftMetricsBAMConfig] BAM credentials request failed, Response: \(String(describing:response))")
                }
                //waiter.signal()
            })

            //let waitTime	= DispatchTime.now() + DispatchTimeInterval.seconds(15)
            //waiter.wait(timeout: waitTime)
    }

    public func refreshBAMConfigWithBasicAuth() {

        Log.debug("[SwiftMetricsBAMConfig] Refreshing BAM Configuration with Basic Auth:  \(sbURL)")

        if(self.backendReady) {
            return
        }

        if self.ingressURL.count > 0 {

            //URLEscape tenantId since can be set via env var

            self.getBAMURLs(authorization: "Basic ")

            self.backendReady  = true

            // TODO: comment out token
            Log.debug("[SwiftMetricsBAMConfig] BAM initialization successful, backend ready to accept requests, URL: \(self.ingressURL) BAM token: \(self.ingressToken)")

            // TODO: don't log token in headers
            Log.debug("[SwiftMetricsBAMConfig] BAM backend Urls: \(self.metricURL) Header: \(self.ingressHeaders)")

        }
    }

    func getBAMURLs(authorization: String) {

        var topoPath: String
        var providerPath: String
        var metricPath: String
        var aarPath: String
        var adrPath: String

        let inPath   = getEnvironmentVal(name: "IBAM_INGRESS_PATH", defVal: INGRESS_PATH)
        topoPath     = getEnvironmentVal(name: "IBAM_TOPO_PATH", defVal: (inPath + "?type=resources"))
        providerPath = getEnvironmentVal(name: "IBAM_PROVIDER_PATH", defVal: (inPath + "?type=providers"))
        metricPath   = getEnvironmentVal(name: "IBAM_METRIC_PATH", defVal: (inPath + "?type=metric"))
        aarPath      = getEnvironmentVal(name: "IBAM_AAR_PATH", defVal: (inPath + "?type=aar/middleware"))
        adrPath      = getEnvironmentVal(name: "IBAM_ADR_PATH", defVal: (inPath + "?type=adr"))

        //URLEscape tenantId since can be set via env var
        let tId = self.tenantId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let me  = "&tenant=" + tId + "&origin=" + self.dcId

        self.ingressHeaders["Authorization"] = authorization + self.ingressToken
        self.ingressHeaders["X-TenantId"] = self.tenantId
        self.ingressHeaders["BM-ApplicationId"] = self.appId

        self.topoURL       = self.ingressURL + topoPath + me
        self.providerURL   = self.ingressURL + providerPath + me
        self.metricURL     = self.ingressURL + metricPath + me
        self.aarURL        = self.ingressURL + aarPath + me
        self.adrURL        = self.ingressURL + adrPath + me
    }

    /*

     BAM Query:

     curl -v -X POST -H 'Accept: application/json' -H 'X-TenantId: a7d34a39-0cee-48cd-bf46-d732a1e15775' -H 'Authorization: bamtoken gdlc49a4a2sj7ns87i9nj2e7saphds7fonohiijvpn9osgn5q2qoturtlmrcdgat' -H 'User-Agent: SwiftDC' -H 'Content-Type: application/json' -H 'X-TransactionId: 8a4f828c-cb35-4fad-85fe-c3c279f04bcd'  -H 'BM-ApplicationId: 55486f24-cd6e-440b-9589-3e2e5000095e' 'https://hcdemo.test.perfmgmt.ibm.com/1.0/data?type=metric&tenant=a7d34a39-0cee-48cd-bf46-d732a1e15775&origin=d41d8cd98f00b204e9800998ecf8427e' -d '{}'

     Response:
     HTTP/1.1 202 Accepted
     Date: Fri, 03 Mar 2017 22:16:09 GMT
     Content-Length: 0
     Content-Language: en-US

     */

    public func makeAPMRequest(perfData: Dictionary<String,Any>, postURL: String) {

        if(!self.backendReady) {
            Log.warning("[SwiftMetricsBAMConfig] Backend is not set")

            if(retryCount < maxRetryLimit) {

                Log.debug("[SwiftMetricsBAMConfig] Retrying to get BAM configuration \(retryCount)")

                self.queue.asyncAfter(deadline: .now() + .milliseconds(5000 * retryCount), execute: {

                    Log.debug("[SwiftMetricsBAMConfig] BAM configuration task started")

                    self.refreshBAMConfig()
                })

                retryCount += 1
            }
        }

        //TODO: don't log token in header
        Log.debug("[SwiftMetricsBAMConfig] Initiating request: \(postURL) Headers: \(self.ingressHeaders) APMData: \(perfData)")

        //BMConfig.makeHttpRequest(apmData: perfData, urlString: postURL, reqType: HTTP_POST, headers: self.ingressHeaders, taskCallback: {
        BMConfig.makeKituraHttpRequest(apmData: perfData, urlString: postURL, reqType: HTTP_POST, headers: self.ingressHeaders, taskCallback: {

            (passed, statusCode, response) in

            Log.debug("[SwiftMetricsBAMConfig] APM data upload: \(postURL) Passed: \(passed) Response status: \(statusCode)  Response: \(String(describing:response))")

        })

    }

    public func getInstanceResourceId(resName: String) -> String {

        let fullStr = self.dcId + resName;
        let str = TokenUtil.md5(resName: fullStr)

        return str
    }

    public func getResourceId(resName: String) -> String {

        let fullStr = self.appId + resName;
        let str = TokenUtil.md5(resName: fullStr)

        return str
    }


    private static func makeKituraHttpRequest(apmData: Dictionary<String,Any>, urlString: String, reqType: String, headers: [String:String], taskCallback: @escaping (Bool, Int, Any?) -> () = doNothing) {

        if(urlString == "") {
            Log.warning("[SwiftMetricsBAMConfig] IngressURL is not set")
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: apmData, options: .prettyPrinted)

                /*let key = "X-TransactionId"
                var headerCopy = headers

                if !headerCopy.keys.contains(key) {
                    headerCopy["X-TransactionId"] = UUID().uuidString.lowercased()
                }*/

                var request = RestRequest(method: .post, url: urlString)

                if(reqType.uppercased() == "GET") {
                    request = RestRequest(method: .get, url: urlString)
                }

                //TODO: don't log token in headers, temporarily changed to info
                //Log.info("Initiating http request  Headers: \(headerCopy) APMData: \(apmData)")
                Log.debug("[SwiftMetricsBAMConfig] Initiating http request  Headers: \(headers) APMData: \(apmData)")
                
                request.messageBody = jsonData
                request.headerParameters = headers
                request.response(completionHandler: { (data, response, error) in
                 
                    if let e = error {
                        //client side error
                        Log.error("[SwiftMetricsBAMConfig] Failed to create connection to \(urlString): " + e.localizedDescription)
                    }
                    else if let httpResponse = response, let receivedData = data {
                        
                        if let ds = String(data: receivedData, encoding: String.Encoding.utf8) {
                            Log.debug("[SwiftMetricsBAMConfig] response as string =>" + ds + "<=")
                        }
                        
                        //var result: String = NSString (data: receivedData, encoding: String.Encoding.utf8.rawValue)
                        let json = try? JSONSerialization.jsonObject(with: receivedData, options: [])
                        
                        switch (httpResponse.statusCode) {
                            
                        case 200...299:
                            
                            // Temporarily put to info as static method is disabling it, will debug later
                            Log.debug("[SwiftMetricsBAMConfig] \(String(describing:request.method)) successful: StatusCode: \(httpResponse.statusCode) Response: \(String(describing:response)), JSON: \(String(describing:json))")
                            
                            taskCallback(true, httpResponse.statusCode, json as Any?)
                            
                        default:
                            Log.error("[SwiftMetricsBAMConfig] \(String(describing:request.method)) request got response \(httpResponse.statusCode) and response \(httpResponse)")
                            taskCallback(false, httpResponse.statusCode, receivedData as Any?)
                        }
                    }
                    else {
                        Log.error("[SwiftMetricsBAMConfig] Error sending data: URL: \(urlString) : Response: \(String(describing:data)), Error: \(String(describing:error))")
                        taskCallback(false, -1, nil)
                    }
                }
                )
            
        } catch {
            Log.warning("[SwiftMetricsBAMConfig] Kitura request failed: \(error.localizedDescription)")
        }

    } // end of makeKituraHttpRequest
}

public class TokenUtil {

    private static func cipher_init(key: String) -> [ String: [UInt8] ] {

        let dig = Digest(using: .sha256).update(string: key)?.final()
        let ks = dig![0..<16]
        let vs = dig![16..<32]
        let k : [UInt8] = Array(ks)
        let v : [UInt8] = Array(vs)
        let rc : [ String: [UInt8] ] = [ "key": k, "iv": v ]
        return rc
    }

    public static func obfuscate(key: String, value: String) -> String {

        let i = cipher_init(key: key)

        if let ky = i["key"], let vl = i["iv"] {
            let c = Cryptor(operation: .encrypt,
                            algorithm: .aes,
                            options:   .pkcs7Padding,
                            key:       ky,
                            iv:        vl)

            let b = c.update(string: value)?.final()

            if let bv = b {
                let d = Data(bytes: bv, count: bv.count).base64EncodedData()

                let s = String(data: d, encoding: String.Encoding.utf8)

                if let sv = s {
                    Log.debug("[SwiftMetricsBAMConfig] Encrypt successful: \(key) val: \(sv)")
                    return sv
                }
            }
        }

        Log.debug("[SwiftMetricsBAMConfig] Encrypt failed: \(key)")
        return ""
    }

    public static func unobfuscate(key: String, value: String) -> String {
        let i = cipher_init(key: key)

        if let ky = i["key"], let vl = i["iv"] {
            let c = Cryptor(operation: .decrypt,
                            algorithm: .aes,
                            options:   .pkcs7Padding,
                            key:       ky,
                            iv:        vl)
            let b = Data(base64Encoded: value)
            if let bv = b {
                let p = c.update(data: bv)?.final()

                if let pv = p {
                    let d = Data(bytes: pv, count: pv.count)
                    let s = String(data: d, encoding: String.Encoding.utf8)

                    if let sv = s {
                        Log.debug("[SwiftMetricsBAMConfig] Decrypt successful: \(key) val: \(value)")
                        return sv
                    }
                }
            }
        }

        Log.debug("[SwiftMetricsBAMConfig] Decrypt failed: \(key) val: \(value)")

        return ""
    }

    public static func md5(resName: String) -> String {

        // String...
        // CryptoUtils.hexString
        let md5Dig = Digest(using: .md5)
        let upd = md5Dig.update(string: resName)
        let digFin = md5Dig.final()
        //let paddedDigest = CryptoUtils.zeroPad(byteArray: digest, blockSize: 16)

        let digestStr = CryptoUtils.hexString(from: digFin) // String(data: digest, encoding: String.Encoding.utf8)

        Log.debug("[SwiftMetricsBAMConfig] MD5 update, \(resName) \(String(describing:upd)) \(digestStr)")

        return digestStr
    }
}

extension Dictionary {
    mutating func update(other:Dictionary) {
        for (key,value) in other {
            self.updateValue(value, forKey:key)
        }
    }
}

////////////// Global Functions

func doNothing(passed: Bool, statusCode: Int, response: Any?) -> () {
    Log.debug("[SwiftMetricsBAMConfig] Status Passed: \(passed), statusCode: \(statusCode) Response: \(String(describing:response))")
    return
}

func stringToJSON(text: String?) -> [String:Any]? {

    guard let actData = text else {
        Log.error("[SwiftMetricsBAMConfig] Could not generate JSON object for null input)")
        return nil
    }

    if(actData.isEmpty) {
        return nil
    }

    guard let data = actData.data(using: String.Encoding.utf8) else {
        Log.error("[SwiftMetricsBAMConfig] Could not generate JSON object as conversion to utf8 failed \(actData)")
        return nil
    }

    do {
        let jsonOpt = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let json = jsonOpt {
            Log.debug("[SwiftMetricsBAMConfig] JSON object: \(json)")
            return json
        }
    }
    catch {
        Log.warning("[SwiftMetricsBAMConfig] Error: " + error.localizedDescription + " Input: \(actData)")
    }
    return nil
}

public func getEnvironmentVal(name: String, defVal : String = "") -> String {

    if let val = processLocalEnv[name] as? String {
        Log.debug("[SwiftMetricsBAMConfig] Env name: \(name), Val: \(val)\n")
        return val
    }
    return defVal
}


/*
 * VCAAP string
 {
 "AvailabilityMonitoring-APD": [
 {
 "credentials": {
 "cred_url": "https://perfbroker-apd.stage1.ng.bluemix.net/1.0/credentials/app/484ac937-03e4-4702-8d0f-e1a1e11c2cd0",
 "token": "McoB6yrVcafXHaO8HtrN9ro8v354WeuFhvdXai13zjez4cK7vJaehjZHQtzSOAed2BqXjJdh/rlahYf5cWKau+aCcrbXq6jtc37kGtkycrA="
 },
 "syslog_drain_url": null,
 "label": "AvailabilityMonitoring-APD",
 "provider": null,
 "plan": "Lite",
 "name": "Availability Monitoring APD-l8",
 "tags": [
 "ibm_created",
 "bluemix_extensions",
 "dev_ops"
 ]
 }
 ],
 "AvailabilityMonitoring": [
 {
 "credentials": {
 "pass": "e1f90e8a-1ee6-40cd-914f-3310e286b4d1",
 "id": "90055aa9-fdf6-4d5f-a610-0e36556b9576",
 "url": "https://perfbroker.stage1.ng.bluemix.net/1.0/credentials/90055aa9-fdf6-4d5f-a610-0e36556b9576"
 },
 "syslog_drain_url": null,
 "label": "AvailabilityMonitoring",
 "provider": null,
 "plan": "Lite",
 "name": "availability-monitoring-auto",
 "tags": [
 "ibm_created",
 "bluemix_extensions",
 "dev_ops"
 ]
 }
 ]
 }
 */
