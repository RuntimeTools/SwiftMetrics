import KituraNet
import SwiftMetrics
import Foundation
import Dispatch

// This structure stores a request and its associated request time
struct requests {
    var request:ServerRequest
    var requestTime:Double
}

// Array of requests for parsing later
var requestStore = [requests]()

private class HttpMonitor: ServerMonitor {
    private let sM:SwiftMetrics
    let queue = DispatchQueue(label: "requestStoreQueue")
    
    init(sm:SwiftMetrics) {
        self.sM=sm
    }

    // Calculate timeInMilliseconds since epoch
    var timeIntervalSince1970MilliSeconds: Double {
        return NSDate().timeIntervalSince1970 * 1000
    } 
    
    // This function is called from Kitura.net when an http request starts
    public func started(request: ServerRequest, response: ServerResponse) {
        queue.async {
            // Only keep 1000 unprocessed calls to conserve memory (this is a guesstimate value)
            if (requestStore.count > 1000) {
                requestStore.removeFirst()
            }
            requestStore.append(requests(request: request, requestTime: self.timeIntervalSince1970MilliSeconds))
        }
        
    }
    
    // This function is called from Kitura.net when an http request finishes
    public func finished(request: ServerRequest?, response: ServerResponse) {
        if request != nil {
            queue.async {
                for (index,req) in requestStore.enumerated() {
                    if request === req.request {
                       self.sM.emitData(HTTPData(timeOfRequest:Int(req.requestTime), url:req.request.urlURL.absoluteString, duration:(self.timeIntervalSince1970MilliSeconds - req.requestTime), statusCode:response.statusCode, requestMethod:req.request.method))
                       requestStore.remove(at:index)
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

public class SwiftMetricsKitura {

    public init(swiftmetricsinstance: SwiftMetrics){
        Monitor.delegate = HttpMonitor(sm: swiftmetricsinstance)
    }
    
    public func enable(sm: SwiftMetrics) {
        Monitor.delegate = HttpMonitor(sm: sm)
    }

    public func disable() {
        Monitor.delegate = nil
    }
}

