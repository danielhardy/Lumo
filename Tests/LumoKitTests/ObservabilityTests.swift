import XCTest
@testable import LumoKit

final class ObservabilityTests: XCTestCase {

    func testWorkflowVocabularyHasStableNamesForEveryRequiredStage() {
        let names = LumoWorkflowStage.allCases.map { String(describing: $0.name) }

        XCTAssertEqual(names, [
            "Launch", "Scan", "Decode", "Render", "Cache", "PhotoSwitch", "Histogram", "Export",
        ])
    }

    func testWorkflowEventsCoverCacheAndSupersededWork() {
        let names = LumoWorkflowEvent.allCases.map { String(describing: $0.name) }

        XCTAssertEqual(names, ["CacheHit", "CacheMiss", "Cancellation", "Coalesced"])
    }

    func testSourceTokensAreStablePrivateSafeAndDistinct() {
        let privatePath = "/Users/example/Private Photos/holiday/raw-001.dng"
        let first = LumoTraceContext(sourceFingerprint: privatePath, quality: "preview")
        let second = LumoTraceContext(sourceFingerprint: privatePath, quality: "preview")
        let different = LumoTraceContext(
            sourceFingerprint: "/Users/example/Private Photos/holiday/raw-002.dng",
            quality: "preview"
        )

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first.sourceToken, different.sourceToken)
        XCTAssertFalse(first.sourceToken.contains("Private"))
        XCTAssertFalse(first.sourceToken.contains("raw-001"))
        XCTAssertEqual(first.sourceToken.count, 16)
    }

    func testEndingAnIntervalMoreThanOnceIsSafe() {
        var interval = LumoSignpostInterval(.render, context: .unknown)
        interval.end()
        interval.end()
    }
}
