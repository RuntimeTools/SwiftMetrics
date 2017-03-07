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
        queue.sync {
            // Only keep 1000 unprocessed calls to conserve memory (this is a guess estimate value)
            if (requestStore.count > 1000) {
                requestStore.removeFirst()
            }
            requestStore.append(requests(request: request, requestTime: self.timeIntervalSince1970MilliSeconds))
        }
    }

    // This function is called from Kitura.net when an http request finishes
    public func finished(request: ServerRequest?, response: ServerResponse) {
        if let request = request {
            queue.sync {
                for (index,req) in requestStore.enumerated() {
                    if request === req.request {
                       print("0 \(req.requestTime)")
      //                       print("1 \(req.request.urlURL.absoluteString)")
                             print("2 \(self.timeIntervalSince1970MilliSeconds - req.requestTime)")
                             print("3 \(response.statusCode)")
                             print("4 \(req.request.method)")
                             print("5 ll done")

                       let temp = HTTPData(timeOfRequest:Int(req.requestTime),
                             url:"req.request.urlURL.absoluteString",
                          duration:(self.timeIntervalSince1970MilliSeconds - req.requestTime),
                            statusCode:response.statusCode, requestMethod:req.request.method)


                       //self.sM.emitData(HTTPData(timeOfRequest:Int(req.requestTime),
                        //     url:req.request.urlURL.absoluteString,
                      //       duration:(self.timeIntervalSince1970MilliSeconds - req.requestTime),
                      //       statusCode:response.statusCode, requestMethod:req.request.method))
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
            print("in SMK publish @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@")
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
