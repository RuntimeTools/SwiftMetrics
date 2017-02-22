import XCTest
@testable import SwiftMetrics

class SwiftMetricsTests: XCTestCase {
    func SwiftMetricsBasicInit() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        do {
            let sm = try SwiftMetrics()
            XCTAssertNotNil(sm, "Cannot find SwiftMetrics instance")
        } catch {
            XCTFail("Unable to instantiate SwiftMetrics")
        }
    }

    static var allTests : [(String, (SwiftMetricsTests) -> () throws -> Void)] {
        return [
            ("SwiftMetricsBasicInit", SwiftMetricsBasicInit),
        ]
    }
}
