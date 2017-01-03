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

// Kitura-Starter contains examples for creating custom routes.
import Foundation
import Kitura
import LoggerAPI
import HeliumLogger
import CloudFoundryEnv
import CloudFoundryDeploymentTracker

do {
  // HeliumLogger disables all buffering on stdout
  HeliumLogger.use(LoggerMessageType.info)
  let controller = try Controller()
  Log.info("Server will be started on '\(controller.url)'.")
  CloudFoundryDeploymentTracker(repositoryURL: "https://github.com/IBM-Bluemix/Kitura-Starter.git", codeVersion: nil).track()
  Kitura.addHTTPServer(onPort: controller.port, with: controller.router)
  // Start Kitura-Starter server
  Kitura.run()
} catch let error {
  Log.error(error.localizedDescription)
  Log.error("Oops... something went wrong. Server did not start!")
}
