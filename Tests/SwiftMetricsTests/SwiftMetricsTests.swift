import XCTest
@testable import SwiftMetrics

class SwiftMetricsTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        XCTAssertEqual(SwiftMetrics().text, "Hello, World!")
    }

    static var allTests : [(String, (SwiftMetricsTests) -> () throws -> Void)] {
        return [
            ("testExample", testExample),
        ]
    }
}
