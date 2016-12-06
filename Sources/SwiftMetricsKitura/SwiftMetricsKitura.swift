import KituraNet
import SwiftMetrics
import Foundation

// This is the structure of the data to emit
public struct HTTPData: SMData {
	public let timeOfRequest: Int
	public let url: String
	public let duration: Double
	public let statusCode: HTTPStatusCode?
	public let requestMethod: String
}

// This structure stores a request and its associated request time
struct requests {
	var request:ServerRequest
	var requestTime:Double
}

// Array of requests for parsing later
var requestStore = [requests]()

private class HttpMonitor: ServerMonitor {
	private let sM:SwiftMetrics
	
	init(sm:SwiftMetrics) {
		self.sM=sm
	}

	// Calculate timeInMilliseconds since epoch
	var timeIntervalSince1970MilliSeconds: Double {
		return NSDate().timeIntervalSince1970 * 1000
	} 
	
	// This function is called from Kitura.net when an httep request starts
	public func started(request: ServerRequest, response: ServerResponse) {
		// Only keep 1000 unprocessed calls to conserve memory (this is a guesstimate value)
		if (requestStore.count > 1000) {
			requestStore.removeFirst()
		}
		requestStore.append(requests(request: request, requestTime: timeIntervalSince1970MilliSeconds))
	}
	
	// This function is called from Kitura.net when an http request finishes
	public func finished(request: ServerRequest?, response: ServerResponse) {
		if request != nil {
			for (index,req) in requestStore.enumerated() {
				if request === req.request {
					sM.emitData(HTTPData(timeOfRequest:Int(req.requestTime), url:(req.request.urlComponents.url?.absoluteString ?? ""), duration:(timeIntervalSince1970MilliSeconds - req.requestTime), statusCode:response.statusCode, requestMethod:req.request.method))
					requestStore.remove(at:index)
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

