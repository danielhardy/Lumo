import XCTest
import CoreGraphics
@testable import LumoKit

final class CanvasNavigationTests: XCTestCase {
    private let landscape = CGRect(x: 0, y: 0, width: 400, height: 200)
    private let viewport = CGSize(width: 300, height: 300)

    func testFitShowsTheWholeImageAndCentersIt() {
        let navigation = CanvasNavigation()
        let transform = navigation.transform(imageExtent: landscape, viewportSize: viewport)

        XCTAssertEqual(transform.scale, 0.75, accuracy: 0.000_001)
        XCTAssertEqual(transform.imageSize, CGSize(width: 300, height: 150))
        XCTAssertEqual(transform.origin, CGPoint(x: 0, y: 75))
    }

    func testFillCoversTheViewport() {
        var navigation = CanvasNavigation()
        navigation.fill()
        let transform = navigation.transform(imageExtent: landscape, viewportSize: viewport)

        XCTAssertEqual(transform.scale, 1.5, accuracy: 0.000_001)
        XCTAssertGreaterThanOrEqual(transform.imageSize.width, viewport.width)
        XCTAssertGreaterThanOrEqual(transform.imageSize.height, viewport.height)
        XCTAssertEqual(transform.origin.y, 0, accuracy: 0.000_001)
    }

    func testPanIsClampedToKeepTheImageCoveringTheViewport() {
        var navigation = CanvasNavigation()
        navigation.setZoom(4)
        navigation.pan(by: CGSize(width: 10_000, height: -10_000),
                       imageExtent: landscape, viewportSize: viewport)
        let transform = navigation.transform(imageExtent: landscape, viewportSize: viewport)

        XCTAssertEqual(transform.origin.x, 0, accuracy: 0.000_001)
        XCTAssertEqual(transform.origin.y, viewport.height - transform.imageSize.height,
                       accuracy: 0.000_001)
    }

    func testInvalidZoomValuesAreSafeAndClamped() {
        var navigation = CanvasNavigation()
        navigation.setZoom(.infinity)
        XCTAssertEqual(navigation.zoom, 1)
        navigation.setZoom(.nan)
        XCTAssertEqual(navigation.zoom, 1)
        navigation.setZoom(-10)
        XCTAssertEqual(navigation.zoom, CanvasNavigation.minimumZoom)
        navigation.setZoom(100)
        XCTAssertEqual(navigation.zoom, CanvasNavigation.maximumZoom)
    }

    func testFocalPointSurvivesViewportResize() {
        var navigation = CanvasNavigation()
        navigation.setZoom(3)
        navigation.pan(by: CGSize(width: -40, height: 25),
                       imageExtent: landscape, viewportSize: viewport)
        let before = navigation.transform(imageExtent: landscape, viewportSize: viewport)
        let resized = navigation.transform(
            imageExtent: landscape, viewportSize: CGSize(width: 500, height: 240)
        )

        XCTAssertNotEqual(before.origin, resized.origin)
        XCTAssertGreaterThanOrEqual(resized.origin.x, 500 - resized.imageSize.width)
        XCTAssertLessThanOrEqual(resized.origin.x, 0)
    }

    func testRenderResolutionGrowsWithZoomButNeverRequestsMoreThanNativeExtent() {
        var navigation = CanvasNavigation()
        XCTAssertEqual(
            navigation.renderResolutionMultiplier(imageExtent: landscape.size, viewportSize: viewport),
            1,
            accuracy: 0.000_001
        )
        navigation.setZoom(4)
        let multiplier = navigation.renderResolutionMultiplier(
            imageExtent: landscape.size, viewportSize: viewport
        )
        XCTAssertEqual(multiplier, 4, accuracy: 0.000_001)

        navigation.setZoom(100)
        XCTAssertLessThanOrEqual(
            navigation.renderResolutionMultiplier(imageExtent: landscape.size, viewportSize: viewport),
            CanvasNavigation.maximumZoom
        )
    }
}
