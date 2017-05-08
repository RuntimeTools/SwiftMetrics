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
import HeliumLogger
import LoggerAPI
import Cryptor
import Foundation
import Dispatch
import KituraRequest
import Configuration

/*
 #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
 import CommonCrypto
 #elseif os(Linux)
 import OpenSSL
 #endif
 */

////////////// Global Variables

public var bamLocalEnv : [String:Any] = ProcessInfo.processInfo.environment

let HTTP_POST: String = "POST"
let HTTP_GET: String = "GET"
let SB_PATH: String = "/1.0/credentials/app/"
let INGRESS_PATH: String = "/1.0/data"


/*
 This Class represents basic BAM Configuration interface. Each environments can subclass this class for
 adaption to their environment
 
 */


public class IBAMConfig {
    
    public var appId    : String
    public var appName  : String
    public var tenantId : String
    public var dcId     : String
    public var logLevel : LoggerMessageType = .info
    
    // service broker url & token if any
    public var sbURL   : String
    //public var sbPath  : String
    public var sbToken : String
    
    
    // BAM server properties required by users
    public var ingressURL: String
    public var ingressToken: String
    
    public var topoURL: String = ""
    public var providerURL: String = ""
    public var metricURL: String = ""
    public var aarURL: String = ""
    public var adrURL: String = ""
    
    // default env vals
    fileprivate var ingressPath: String
    fileprivate var topoPath: String
    fileprivate var providerPath: String
    fileprivate var metricPath: String
    fileprivate var aarPath: String
    fileprivate var adrPath: String
    fileprivate var serviceName: String
    
    fileprivate var isDebugEnabled : Bool = false
    
    fileprivate var maxRetryLimit : Int = 3
    fileprivate var retryCount = 0
    // by default queue is serial attributes: .serial
    fileprivate let queue = DispatchQueue(label: "com.ibm.bam", qos: .background, target: nil)
    //fileprivate let waiter = DispatchSemaphore(value: 0)
    
    //public var bamLocalEnv : [String:String] = [:]
    
    public var ingressHeaders : [String: String] = [
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "SwiftDC"
    ]
    
    fileprivate var backendReady: Bool = false
    
    //This will get overwritten by VCAP_SERVICES and VCAP_APPLICATION below.
    //  These env should take precedence so even in Bluemix they can be
    //  use as overrides to VCAP_* not the other way around
    init() {
        
        let inPath = getEnvironmentVal(name: "IBAM_INGRESS_PATH", defVal: INGRESS_PATH)
        let logLevelString = getEnvironmentVal(name: "IBAM_LOG_LEVEL", defVal: ".info")
        
        appId        = getEnvironmentVal(name: "IBAM_APPLICATION_ID")
        appName      = getEnvironmentVal(name: "IBAM_APPLICATION_NAME")
        tenantId     = getEnvironmentVal(name: "X-TenantId")
        dcId         = UUID().uuidString.lowercased()
        sbURL        = getEnvironmentVal(name: "IBAM_SB_URL")
        sbToken      = getEnvironmentVal(name: "IBAM_SB_TOKEN")
        //sbPath     = bamLocalEnv["IBAM_SB_PATH"] ?? SB_PATH
        ingressURL   = getEnvironmentVal(name: "IBAM_INGRESS_URL")
        ingressPath  = inPath
        ingressToken = getEnvironmentVal(name: "IBAM_TOKEN")
        
        topoPath     = getEnvironmentVal(name: "IBAM_TOPO_PATH", defVal: (inPath + "?type=resources"))
        providerPath = getEnvironmentVal(name: "IBAM_PROVIDER_PATH", defVal: (inPath + "?type=providers"))
        metricPath   = getEnvironmentVal(name: "IBAM_METRIC_PATH", defVal: (inPath + "?type=metric"))
        aarPath      = getEnvironmentVal(name: "IBAM_AAR_PATH", defVal: (inPath + "?type=aar/middleware"))
        adrPath      = getEnvironmentVal(name: "IBAM_ADR_PATH", defVal: (inPath + "?type=adr"))
        serviceName  = getEnvironmentVal(name: "IBAM_SVC_NAME", defVal: "AvailabilityMonitoring")
        
        if let limit = Int(getEnvironmentVal(name: "IBAM_MAX_RETRY_LIMIT", defVal: "3")) {
            self.maxRetryLimit = limit
        }
        
        logLevel = stringToLoggerMessageType(logLevelString: logLevelString)
        HeliumLogger.use(logLevel)
        
        populateLocalEnvironment() // must be the first line
        
    }
    
    
    private func populateLocalEnvironment() {
        
        let debugEnvStr = getEnvironmentVal(name: "IBAM_DEBUG_ENV")
        
        if !debugEnvStr.isEmpty {
            Log.info("DEBUG environment is set: \(debugEnvStr)")
            isDebugEnabled = true
        }
        
        if let envDic = stringToJSON(text: debugEnvStr) {
            for (key, val) in envDic {
                bamLocalEnv[key] = val
            }
        }
        
        Log.info("## Environment: \(bamLocalEnv)")
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

public class BMConfig : IBAMConfig {
    
    public var spaceId : String = ""
    public var instanceId : String = ""
    public var instanceIndex : String = ""
    //public var cfAppEnv : AppEnv?
    var configManager: ConfigurationManager?
    
    // lazily initialized
    static let sharedInstance: BMConfig = {
        let instance = BMConfig()
        // any set up code goes here
        return instance
    }()
    
    private override init() {
        super.init()
        
        cloudFoundryBasedInitialization()
        vcapEnvBasedInitialization()
    }
    
    // Initialize environment based on CloudFoundry Object
    private func cloudFoundryBasedInitialization() {
        
        self.configManager = ConfigurationManager()
        self.configManager?.load(.environmentVariables)
        
        Log.info("## ConfigManager: \(String(describing:self.configManager))")
        
        if let app = self.configManager?.getApp() {
            
            Log.info("Retrieving application info from CloudFoundryEnv \(app)")
            
            if self.appId.isEmpty {
                self.appId = app.id
            }
            
            if self.spaceId.isEmpty {
                self.spaceId = app.spaceId
            }
            
            if self.appName.isEmpty {
                self.appName = app.name
            }
            
            if self.instanceId.isEmpty {
                self.instanceId = app.instanceId
            }
            
            if self.instanceIndex.isEmpty {
                self.instanceIndex = "\(app.instanceIndex)"
            }
        }
        
        if self.tenantId.isEmpty {
            self.tenantId = self.spaceId
        }
        
        // VCAP_SERVICES initialization
        // Service name can be changed by the user and hence name based query is NOT used
        // Use service label instead
        
        var servCreds : [String:Any] = [:]
        
        //if let vcapServices = self.cfAppEnv?.getServices() {
        if let vcapServices = self.configManager?.getServices() {
            Log.info("Retrieving vcapservice info from CloudFoundryEnv \(vcapServices)")
            
            for (serName, service) in vcapServices {
                
                if(service.label.range(of: self.serviceName) != nil) {
                    if let creds = service.credentials {
                        Log.info("Retrieving cred info from CloudFoundryEnv \(creds)")
                        servCreds = creds
                        Log.info("cloudFoundryBasedInitialization: Service credentials successfully obtained for \(serName) Creds: \(servCreds)")
                        break
                    }
                }
            }
        }
        
        Log.info("cloudFoundryBasedInitialization: \(servCreds)")
        
        var tmpSBToken: String = self.sbToken
        
        if tmpSBToken.isEmpty, let sbt = servCreds["token"] as? String {
            tmpSBToken = sbt
        }
        
        if tmpSBToken.characters.count > 0 {
            self.sbToken = TokenUtil.unobfuscate(key: appId, value: tmpSBToken)
            Log.info("SB token set successfully \(self.sbToken)")
        }
        
        if self.sbURL.isEmpty, let surl = servCreds["cred_url"] as? String {
            self.sbURL = surl + SB_PATH + self.appId
            Log.info("SB URL set successfully \(self.sbURL)")
        }
        
        //ABD: Not sure this is the right thing to do in bluemix env?
        //     appName can change fairly frequently and instanceId always
        //     changes unless should be new dc
        //  maybe: dcId = TokenUtil.md5(resName: self.appId + self.instance_index)?
        dcId = TokenUtil.md5(resName: self.appId + self.instanceIndex)
        
        Log.info("BMConfig default init, SBURL: \(self.sbURL) SBToken: \(tmpSBToken) ServCreds: \(servCreds) tenantId: \(self.tenantId) AppName: \(self.appName) InstanceId: \(self.instanceId) InstanceIndex: \(self.instanceIndex) DCID: \(dcId)")
        
        self.refreshBAMConfigTask()

        
    }
    
    // This can be temporary till the CF bug is fixed
    // TODO: take it out once bug fixed
    
    private func vcapEnvBasedInitialization() {
        
        if !self.sbURL.isEmpty {
            Log.info("BAM Config already initialized using CloudFoundry env, returning..")
            return
        }
        
        
        //let configManager = ConfigurationManager()
        
        //if let app = self.cfAppEnv?.getApp() {
        if let app = self.configManager?.getApp() {
            Log.debug("Retrieving application info from CloudFoundryEnv")
            if self.appId.isEmpty {
                self.appId = app.id
            }
            
            if self.spaceId.isEmpty {
                self.spaceId = app.spaceId
            }
            
            if self.appName.isEmpty {
                self.appName = app.name
            }
            
            if self.instanceId.isEmpty {
                self.instanceId = app.instanceId
            }
            
            if self.instanceIndex.isEmpty {
                self.instanceIndex = "\(app.instanceIndex)"
            }
        }
        
        if let vApp = stringToJSON(text: getEnvironmentVal(name: "VCAP_APPLICATION")) {
            //In dev env, CloudFoundryEnv doesn't always work
            Log.debug("Retrieving application info from VCAP_APPLICATION env var")
            if self.appId.isEmpty {
                self.appId = vApp["application_id"] as? String ?? UUID().uuidString.lowercased()
            }
            if self.spaceId.isEmpty {
                self.spaceId = vApp["space_id"] as? String ?? UUID().uuidString.lowercased()
            }
            if self.appName.isEmpty {
                self.appName = vApp["application_name"] as? String ?? ""
            }
            if self.instanceId.isEmpty {
                self.instanceId = vApp["instance_id"] as? String ?? UUID().uuidString.lowercased()
            }
            
            if self.instanceIndex.isEmpty {
                self.instanceIndex = vApp["instance_index"] as? String ?? UUID().uuidString.lowercased()
            }
        }
        if self.tenantId.isEmpty {
            self.tenantId = self.spaceId
        }
        
        
        let servName = self.serviceName
        
        Log.info("Using IBAM_SVC_NAME \(servName)")
        
        //We cannot use cfAppEnv here because it gets the services by
        //  name, not type/id, and the customer can rename the service to
        //  anything they want.
        var servCreds : [String:Any] = [:]
        let svcs = stringToJSON(text: getEnvironmentVal(name: "VCAP_SERVICES")) ?? [:]
        
        Log.info("Retrieving vcapservice info from env variable \(svcs)")
        
        for (serName, service) in svcs {
            Log.debug("Service Name: \(serName) Service: \(service)")
            
            if let svcArr = service as? [Any] {
                
                for svcObj in svcArr {
                    if let servDic = svcObj as? [String:Any] {
                        if let label = servDic["label"] as? String {
                            if(label.range(of: self.serviceName) != nil) {
                                if let creds = servDic["credentials"] as? [String: Any] {
                                    Log.info("Retrieving cred info from CloudFoundryEnv \(creds)")
                                    servCreds = creds
                                    Log.info("cloudFoundryBasedInitialization: Service credentials successfully obtained for \(serName) Creds: \(servCreds)")
                                    break
                                }
                            }
                        }
                    }
                }
                
            }
            
        }
        
        
        Log.info("cloudFoundryBasedInitialization, service creds: \(servCreds)")
        
        var tmpSBToken: String = self.sbToken
        
        if tmpSBToken.isEmpty, let sbt = servCreds["token"] as? String {
            tmpSBToken = sbt
        }
        
        if tmpSBToken.characters.count > 0 {
            self.sbToken = TokenUtil.unobfuscate(key: appId, value: tmpSBToken)
        }
        
        if self.sbURL.isEmpty, let surl = servCreds["cred_url"] as? String {
            self.sbURL = surl + SB_PATH + self.appId
        }
        
        dcId = TokenUtil.md5(resName: self.appName + self.instanceIndex)
        
        Log.info("BMConfig default init, SBURL: \(self.sbURL) SBToken: \(tmpSBToken) ServCreds: \(servCreds) tenantId: \(self.tenantId) AppName: \(self.appName) InstanceId: \(self.instanceId) InstanceIndex: \(self.instanceIndex) DCID: \(dcId)")
        
        
        self.refreshBAMConfigTask()
        
        Log.info("BMConfig initialized")

        
    }
    
    
    
    /*
     SB Query:
     curl -H 'Accept: application/json' -H 'X-TenantId: a7d34a39-0cee-48cd-bf46-d732a1e15775' -H 'Authorization: bamtoken gdlc49a4a2sj7ns87i9nj2e7saphds7fonohiijvpn9osgn5q2qoturtlmrcdgat' -H 'User-Agent: SwiftDC' 'https://perfbroker-apd.stage1.ng.bluemix.net/1.0/credentials/app/55486f24-cd6e-440b-9589-3e2e5000095e'
     
     Curl response:
     
     {"backend_url":"https:\/\/hcdemo.test.perfmgmt.ibm.com","token":"gdlc49a4a2sj7ns87i9nj2e7saphds7fonohiijvpn9osgn5q2qoturtlmrcdgat"}
     */
    
    public func refreshBAMConfig() {
        if(retryCount < maxRetryLimit) {
            
            Log.info("Retrying to get BAM configuration \(retryCount)")
            
            self.queue.asyncAfter(deadline: .now() + .milliseconds(5000 * retryCount), execute: {
                
                Log.info("BAM configuration task started")
                
                self.refreshBAMConfigTask()
            })
            
            retryCount += 1
        }
    }
    
    func refreshBAMConfigTask() {
        
        Log.info("## Refreshing BAM Configuration:  \(sbURL)")
        
        
        if(self.backendReady) {
            return
        }
        
        if self.ingressURL.characters.count > 0 && self.ingressToken.characters.count > 0 {
            refreshBAMConfigWithBasicAuth()
            return
        }
        
        //this does not appear to be threadsafe
        if self.sbURL.characters.count > 0 {
            
            /*"cred_url": "https://perfbroker-apd.stage1.ng.bluemix.net/1.0/credentials/app/55486f24-cd6e-440b-9589-3e2e5000095e"
             */
            
            let auth = "bamtoken " + self.sbToken
            let hdrs = ["Accept": "application/json",
                        "X-TenantId": self.tenantId,
                        "Authorization": auth,
                        "User-Agent": "SwiftDC"]
            
            Log.info("## BAM credentials request initiated, URL: \(sbURL) BAM headers: \(hdrs) ")
            
            
            
            //makeHttpRequest should probably retry internally?
            //BMConfig.makeHttpRequest(apmData: [:], urlString: self.sbURL, reqType: HTTP_GET, headers: hdrs, taskCallback: {
            
            BMConfig.makeKituraHttpRequest(apmData: [:], urlString: self.sbURL, reqType: HTTP_GET, headers: hdrs, taskCallback: {
                (passed, statusCode, response) in
                
                if(passed) {
                    if let config = response as? [String:Any] {
                        if let bu = config["backend_url"] as? String {
                            
                            Log.info("Backend url obtained: \(bu)")
                            let newString = bu.replacingOccurrences(of: " ", with: "", options: .literal, range: nil)
                            
                            Log.info("Backend url refined: \(newString)")
                            
                            self.ingressURL = newString
                        }
                        
                        if let it = config["token"] as? String {
                            self.ingressToken = it
                        }
                        
                        //URLEscape tenantId since can be set via env var
                        let tId = self.tenantId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
                        let me  = "&tenant=" + tId + "&origin=" + self.dcId
                        
                        self.ingressHeaders["Authorization"] = "bamtoken " + self.ingressToken
                        self.ingressHeaders["X-TenantId"] = self.tenantId
                        self.ingressHeaders["BM-ApplicationId"] = self.appId
                        
                        self.topoURL       = self.ingressURL + self.topoPath + me
                        self.providerURL   = self.ingressURL + self.providerPath + me
                        self.metricURL     = self.ingressURL + self.metricPath + me
                        self.aarURL        = self.ingressURL + self.aarPath + me
                        self.adrURL        = self.ingressURL + self.adrPath + me
                        self.backendReady  = true
                        
                        // TODO: comment out token
                        Log.info("BAM initialization successful, backend ready to accept requests, URL: \(self.ingressURL) BAM token: \(self.ingressToken)")
                        
                        // TODO: don't log token in headers
                        Log.info("BAM backend Urls: \(self.metricURL) Header: \(self.ingressHeaders)")
                    }
                }
                else {
                    Log.info("BAM credentials request failed, Response: \(String(describing:response))")
                }
                //waiter.signal()
            })

            //let waitTime	= DispatchTime.now() + DispatchTimeInterval.seconds(15)
            //waiter.wait(timeout: waitTime)
        }
    }
    
    public func refreshBAMConfigWithBasicAuth() {
        
        Log.info("## Refreshing BAM Configuration with Basic Auth:  \(sbURL)")
        
        if(self.backendReady) {
            return
        }
        
        if self.ingressURL.characters.count > 0 {
            
            //URLEscape tenantId since can be set via env var
            let tId = self.tenantId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            let me  = "&tenant=" + tId + "&origin=" + self.dcId
            
            self.ingressHeaders["Authorization"] = "Basic " + self.ingressToken
            self.ingressHeaders["X-TenantId"] = self.tenantId
            self.ingressHeaders["BM-ApplicationId"] = self.appId
            
            self.topoURL       = self.ingressURL + self.topoPath + me
            self.providerURL   = self.ingressURL + self.providerPath + me
            self.metricURL     = self.ingressURL + self.metricPath + me
            self.aarURL        = self.ingressURL + self.aarPath + me
            self.adrURL        = self.ingressURL + self.adrPath + me
            self.backendReady  = true
            
            // TODO: comment out token
            Log.info("BAM initialization successful, backend ready to accept requests, URL: \(self.ingressURL) BAM token: \(self.ingressToken)")
            
            // TODO: don't log token in headers
            Log.info("BAM backend Urls: \(self.metricURL) Header: \(self.ingressHeaders)")
            
        }
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
            Log.warning("Backend is not set")
            
            if(retryCount < maxRetryLimit) {
                
                Log.info("Retrying to get BAM configuration \(retryCount)")
                
                self.queue.asyncAfter(deadline: .now() + .milliseconds(5000 * retryCount), execute: {
                    
                    Log.info("BAM configuration task started")
                    
                    self.refreshBAMConfig()
                })
                
                retryCount += 1
            }
        }
        
        //TODO: don't log token in header
        Log.debug("Initiating request: \(postURL) Headers: \(self.ingressHeaders) APMData: \(perfData)")
        
        //BMConfig.makeHttpRequest(apmData: perfData, urlString: postURL, reqType: HTTP_POST, headers: self.ingressHeaders, taskCallback: {
        BMConfig.makeKituraHttpRequest(apmData: perfData, urlString: postURL, reqType: HTTP_POST, headers: self.ingressHeaders, taskCallback: {
            
            (passed, statusCode, response) in
            
            Log.info(" APM data upload: \(postURL) Passed: \(passed) Response status: \(statusCode)  Response: \(String(describing:response))")
            
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
    
    
    public static func makeHttpRequest(apmData: Dictionary<String,Any>, urlString: String, reqType: String, headers: [String:String], taskCallback: @escaping (Bool, Int, Any?) -> () = doNothing) {
        
        if(urlString.isEmpty) {
            Log.warning("urlString parameter is not set")
            return
        }
        
        let url = URL(string:urlString)!
        let session = URLSession(configuration: URLSessionConfiguration.default)
        //let request : MutableURLRequest = MutableURLRequest(url:url)
        
        var request : URLRequest = URLRequest(url:url)
        
        //request.url = URL(string: urlString)
        request.httpMethod = reqType.uppercased()
        request.timeoutInterval = 30
        
        for (key, val) in headers {
            request.addValue(val, forHTTPHeaderField: key)
        }
        
        //transaction ID is required by backend
        let key = "X-TransactionId"
        if !headers.keys.contains(key) {
            request.addValue(UUID().uuidString.lowercased(), forHTTPHeaderField: key)
        }
        
        if reqType != "GET" {
            if let jsonData = try? JSONSerialization.data(withJSONObject: apmData, options: []) {
                request.httpBody = jsonData
            }
            else {
                let res = "Not making http request. Error converting input data into JSON: \(urlString)"
                Log.error(res)
                
                return
            }
        }
        
        //TODO: don't log token in headers, temporarily changed to info
        Log.info("Initiating http request \(request) Headers: " +
            request.allHTTPHeaderFields!.description +
            " APMData: \(apmData)")
        
        // make the http request once all the params are populated
        
        let task = session.dataTask(with: request as URLRequest, completionHandler: {
            data, response, error in
            
            if let e = error {
                //client side error
                Log.error("Failed to create connection to \(url): " + e.localizedDescription)
            }
            else if let httpResponse = response as? HTTPURLResponse, let receivedData = data {
                
                if let ds = String(data: receivedData, encoding: String.Encoding.utf8) {
                    Log.debug("response as string =>" + ds + "<=")
                }
                
                //var result: String = NSString (data: receivedData, encoding: String.Encoding.utf8.rawValue)
                let json = try? JSONSerialization.jsonObject(with: receivedData, options: [])
                
                switch (httpResponse.statusCode) {
                    
                case 200...299:
                    
                    // Temporarily put to info as static method is disabling it, will debug later
                    Log.info("\(String(describing:request.httpMethod)) successful: StatusCode: \(httpResponse.statusCode) Response: \(String(describing:response)), JSON: \(String(describing:json))")
                    
                    taskCallback(true, httpResponse.statusCode, json as Any?)
                    
                default:
                    Log.error("\(String(describing:request.httpMethod)) request got response \(httpResponse.statusCode) and response \(httpResponse)")
                    taskCallback(false, httpResponse.statusCode, receivedData as Any?)
                }
            }
            else {
                Log.error("Error sending data: URL: \(urlString) : Response: \(String(describing:data)), Error: \(String(describing:error))")
                taskCallback(false, -1, nil)
            }
            
        })
        
        task.resume()
        
    }
    
    
    
    private static func makeKituraHttpRequest(apmData: Dictionary<String,Any>, urlString: String, reqType: String, headers: [String:String], taskCallback: @escaping (Bool, Int, Any?) -> () = doNothing) {
        
        if(urlString == "") {
            Log.warning("IngressURL is not set")
            return
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: apmData, options: .prettyPrinted)
            let decoded = try JSONSerialization.jsonObject(with: jsonData, options: [])
            if let dictFromJSON = decoded as? [String:Any] {
                
                
                let key = "X-TransactionId"
                var headerCopy = headers
                
                if !headerCopy.keys.contains(key) {
                    headerCopy["X-TransactionId"] = UUID().uuidString.lowercased()
                }
                
                var kitReqType = Request.Method.post
                
                if(reqType.uppercased() == "GET") {
                    kitReqType = Request.Method.get
                }
                
                //TODO: don't log token in headers, temporarily changed to info
                Log.info("Initiating http request  Headers: \(headerCopy) APMData: \(apmData)")
                
                KituraRequest.request(kitReqType,
                                      urlString,
                                      parameters: dictFromJSON,
                                      encoding: JSONEncoding.default,
                                      headers: headers
                    ).response {
                        request, response, data, error in
                        if request != nil {
                            Log.debug("sendMetrics:Request: \(request!)")
                        }
                        if response != nil {
                            Log.debug(" sendMetrics:Response: \(response!)")
                        }
                        if data != nil {
                            Log.debug(" sendMetrics:Data: \(data!)")
                        }
                        //Log.debug("sendMetrics:Request: \(request!)")
                        //Log.debug(" sendMetrics:Response: \(response!)")
                        //Log.debug(" sendMetrics:Data: \(data!)")
                        Log.debug(" sendMetrics:Error: \(String(describing:error))")
                        
                        
                        if let e = error {
                            //client side error
                            Log.error("Failed to create connection to \(urlString): " + e.localizedDescription)
                        }
                        else if let httpResponse = response, let receivedData = data {
                            
                            if let ds = String(data: receivedData, encoding: String.Encoding.utf8) {
                                Log.debug("response as string =>" + ds + "<=")
                            }
                            
                            //var result: String = NSString (data: receivedData, encoding: String.Encoding.utf8.rawValue)
                            let json = try? JSONSerialization.jsonObject(with: receivedData, options: [])
                            
                            switch (httpResponse.httpStatusCode.rawValue) {
                                
                            case 200...299:
                                
                                // Temporarily put to info as static method is disabling it, will debug later
                                Log.info("\(String(describing:request?.method)) successful: StatusCode: \(httpResponse.statusCode) Response: \(String(describing:response)), JSON: \(String(describing:json))")
                                
                                taskCallback(true, httpResponse.httpStatusCode.rawValue, json as Any?)
                                
                            default:
                                Log.error("\(String(describing:request?.method)) request got response \(httpResponse.httpStatusCode.rawValue) and response \(httpResponse)")
                                taskCallback(false, httpResponse.httpStatusCode.rawValue, receivedData as Any?)
                            }
                        }
                        else {
                            Log.error("Error sending data: URL: \(urlString) : Response: \(String(describing:data)), Error: \(String(describing:error))")
                            taskCallback(false, -1, nil)
                        }
                }
            }
        } catch {
            Log.warning(" Kitura request failed: \(error.localizedDescription)")
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
                    Log.debug("Encrypt successful: \(key) val: \(sv)")
                    return sv
                }
            }
        }
        
        Log.debug("Encrypt failed: \(key)")
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
                        Log.debug("Decrypt successful: \(key) val: \(value)")
                        return sv
                    }
                }
            }
        }
        
        Log.debug("Decrypt failed: \(key) val: \(value)")
        
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
        
        Log.debug("MD5 update, \(resName) \(String(describing:upd)) \(digestStr)")
        
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
    Log.debug("Status Passed: \(passed), statusCode: \(statusCode) Response: \(String(describing:response))")
    return
}

func stringToJSON(text: String?) -> [String:Any]? {
    
    guard let actData = text else {
        Log.error("Could not generate JSON object for null input)")
        return nil
    }
    
    if(actData.isEmpty) {
        return nil
    }
    
    
    guard let data = actData.data(using: String.Encoding.utf8) else {
        Log.error("Could not generate JSON object as conversion to utf8 failed \(actData)")
        return nil
    }
    
    do {
        let jsonOpt = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        if let json = jsonOpt {
            Log.debug("JSON object: \(json)")
            return json
        }
    }
    catch {
        Log.debug("Error: " + error.localizedDescription + " Input: \(actData)")
    }
    
    return nil
}

public func getEnvironmentVal(name: String, defVal : String = "") -> String {
    
    if let val = bamLocalEnv[name] as? String {
        
        Log.debug("Env name: \(name), Val: \(val)\n")
        
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

