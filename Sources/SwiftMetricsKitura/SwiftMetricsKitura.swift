/**
* Copyright IBM Corporation 2017
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

import KituraNet
import SwiftMetrics
import Foundation
import Dispatch

public struct HTTPData: SMData {
  public let timeOfRequest: Int
  public let url: String
  public let duration: Double
  public let statusCode: HTTPStatusCode?
  public let requestMethod: String
}

// This structure stores a request and its associated request time
struct requests {
    var request: ServerRequest
    var requestTime: Double
}

// Array of requests for parsing later
var requestStore = [requests]()

private class HttpMonitor: ServerMonitor {
    private let sM: SwiftMetrics
    let queue = DispatchQueue(label: "requestStoreQueue")

    init(swiftMetricsInstance: SwiftMetrics) {
        self.sM = swiftMetricsInstance
    }

    // Calculate timeInMilliseconds since epoch
    var timeIntervalSince1970MilliSeconds: Double {
        return NSDate().timeIntervalSince1970 * 1000
    }

    // This function is called from Kitura.net when an http request starts
    public func started(request: ServerRequest, response: ServerResponse) {
        let requestTemp = request
        let _ = requestTemp.urlURL
            queue.sync {
                // Only keep 1000 unprocessed calls to conserve memory (this is a guess estimate value)
                if (requestStore.count > 1000) {
                    requestStore.removeFirst()
                }
                requestStore.append(requests(request: requestTemp, requestTime: self.timeIntervalSince1970MilliSeconds))
            }

    }

    // This function is called from Kitura.net when an http request finishes
    public func finished(request: ServerRequest?, response: ServerResponse) {
        let _ = response
        if let requestTemp = request {
            queue.sync {
                for (index,req) in requestStore.enumerated() {
                    if requestTemp === req.request {
                        self.sM.emitData(HTTPData(timeOfRequest:Int(req.requestTime),
                             url:req.request.urlURL.absoluteString,
                             duration:(self.timeIntervalSince1970MilliSeconds - req.requestTime),
                             statusCode:response.statusCode, requestMethod:req.request.method))
                        requestStore.remove(at:index)
                        break
                       }
                    }
                }
            }
        }

}

public typealias httpClosure = (HTTPData) -> ()

public extension SwiftMonitor.EventEmitter {

    static var httpObservers: [httpClosure] = []

    static func publish(data: HTTPData) {
        for process in httpObservers {
            process(data)
        }
    }

    static func subscribe(callback: @escaping httpClosure) {
        httpObservers.append(callback)
    }

}

public extension SwiftMonitor {

  public func on(_ callback: @escaping httpClosure) {
    EventEmitter.subscribe(callback: callback)
  }

  func raiseEvent(data: HTTPData) {
    EventEmitter.publish(data: data)
  }

}

public extension SwiftMetrics {

  public func emitData(_ data: HTTPData) {
    if let monitor = swiftMon {
      monitor.raiseEvent(data: data)
    }
  }

}

public class SwiftMetricsKitura {

    public init(swiftMetricsInstance: SwiftMetrics){
        Monitor.delegate = HttpMonitor(swiftMetricsInstance: swiftMetricsInstance)
    }

    public func enable(swiftMetricsInstance: SwiftMetrics) {
        Monitor.delegate = HttpMonitor(swiftMetricsInstance: swiftMetricsInstance)
    }

    public func disable() {
        Monitor.delegate = nil
    }
}
