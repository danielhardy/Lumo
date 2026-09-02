import CoreGraphics
import XCTest
@testable import LumoKit

final class ResolutionPlannerTests: XCTestCase {
    private let native = CGSize(width: 6_000, height: 4_000)

    func testQuarterCropRequestsNativeDetailWhenItWouldOtherwiseUpscale() {
        var planner = ResolutionPlanner()
        let plan = planner.plan(
            nativeExtent: native,
            crop: CropAdjustments(normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25)),
            viewportSize: CGSize(width: 1_600, height: 1_200)
        )

        XCTAssertEqual(plan.sourceSize, native)
        XCTAssertTrue(plan.isNativeResolution)
        XCTAssertEqual(plan.cropRect, CGRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25))
    }

    func testFitDetailIsDiscreteAndHysteresisBoundsResizeTransitions() {
        var planner = ResolutionPlanner()
        let initial = planner.plan(nativeExtent: native, viewportSize: CGSize(width: 1_620, height: 1_080))
        XCTAssertEqual(initial.scale, 0.5, "the first adequate level should be reusable")
        XCTAssertEqual(initial.sourceSize, CGSize(width: 3_000, height: 2_000))

        let nearBoundary = planner.plan(nativeExtent: native, viewportSize: CGSize(width: 1_500, height: 1_000))
        XCTAssertEqual(nearBoundary.level, initial.level,
                       "small resize changes must not thrash the selected level")

        let lower = planner.plan(nativeExtent: native, viewportSize: CGSize(width: 1_200, height: 800))
        XCTAssertEqual(lower.scale, 0.25)

        let upgrade = planner.plan(nativeExtent: native, viewportSize: CGSize(width: 1_560, height: 1_040))
        XCTAssertEqual(upgrade.scale, 0.5)
    }

    func testPanelBackingPixelsAndZoomDriveThePlanWithoutExceedingNativeBounds() {
        var planner = ResolutionPlanner()
        let sideBySide = planner.plan(
            nativeExtent: native, viewportSize: CGSize(width: 800, height: 1_200)
        )
        XCTAssertEqual(sideBySide.sourceSize, CGSize(width: 1_500, height: 1_000))

        var navigation = CanvasNavigation()
        navigation.setZoom(8)
        let deep = planner.plan(
            nativeExtent: native, viewportSize: CGSize(width: 800, height: 1_200), navigation: navigation
        )
        XCTAssertEqual(deep.sourceSize, native)
        XCTAssertLessThanOrEqual(deep.sourceSize.width, native.width)
        XCTAssertLessThanOrEqual(deep.sourceSize.height, native.height)
        XCTAssertGreaterThan(deep.visibleSourceRect.width, 0)
        XCTAssertLessThan(deep.visibleSourceRect.width, native.width)
    }
}
