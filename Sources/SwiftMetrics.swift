import loaderCoreFunctions

public class SwiftMetrics {

    let loaderApi: loaderCoreFunctions
    let SWIFTMETRICS_VERSION = "99.99.99.29991231"
    var running = 1

    public init() {
       
        self.loaderApi = loader_entrypoint().pointee
        self.loadProperties()
        loaderApi.setLogLevels()
        loaderApi.setProperty("agentcore.version", loaderApi.getAgentVersion())
        loaderApi.setProperty("swiftmetrics.version", SWIFTMETRICS_VERSION)
        loaderApi.logMessage(info, "Swift Application Metrics")
    }

    private func loadProperties() {
    
       _ = loaderApi.loadPropertiesFile("/vagrant/deploy/healthcenter.properties") 
    }

    public func spath(path: String) {
        loaderApi.setProperty("com.ibm.diagnostics.healthcenter.plugin.path", path)
    }

    public func stop() {
        if (running == 0) {
            running = 1
            loaderApi.stop()
            loaderApi.shutdown()
        }
    }
  
    public func start() {
        if (running == 1) {
            running = 0
            _ = loaderApi.initialize()
            loaderApi.setProperty("com.ibm.diagnostics.healthcenter.mqtt", "on")
            loaderApi.start()
        }
    }

}
