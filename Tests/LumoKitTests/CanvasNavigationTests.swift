import XCTest
import CoreGraphics
import CoreImage
import Combine
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

@MainActor
final class CanvasObservationTests: XCTestCase {
    func testHighFrequencyCanvasAndCropUpdatesBypassBroadModelPublisher() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.sourceImage = CIImage(color: .gray).cropped(
            to: CGRect(x: 0, y: 0, width: 100, height: 80)
        )

        var appChanges = 0
        var canvasChanges = 0
        var inspectorChanges = 0
        let appSubscription = viewModel.objectWillChange.sink { _ in appChanges += 1 }
        let canvasSubscription = viewModel.canvasState.objectWillChange.sink {
            _ in canvasChanges += 1
        }
        let inspectorSubscription = viewModel.inspectorState.objectWillChange.sink {
            _ in inspectorChanges += 1
        }

        // A wheel/pinch update is presentation-only and must not fan out through AppViewModel.
        viewModel.setCanvasZoom(2)
        XCTAssertEqual(appChanges, 0)
        XCTAssertGreaterThan(canvasChanges, 0)

        // Crop-handle movement has the same contract. The opening transition may update status,
        // so begin first and measure only the pointer-frequency draft mutation.
        viewModel.beginCrop()
        appChanges = 0
        canvasChanges = 0
        viewModel.updateCropDraft(CGRect(x: 0.1, y: 0.1, width: 0.7, height: 0.7))
        XCTAssertEqual(appChanges, 0)
        XCTAssertGreaterThan(canvasChanges, 0)

        // Inspector chrome is independently observable and is not forwarded through the broad
        // model publisher either.
        appChanges = 0
        viewModel.inspectorState.tab = .effects
        XCTAssertEqual(appChanges, 0)
        XCTAssertGreaterThan(inspectorChanges, 0)

        withExtendedLifetime((appSubscription, canvasSubscription, inspectorSubscription)) {}
    }

    func testSourceResetClearsNavigationAndCropTransientState() {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        viewModel.sourceImage = CIImage(color: .gray).cropped(
            to: CGRect(x: 0, y: 0, width: 100, height: 80)
        )
        viewModel.setCanvasZoom(3)
        viewModel.beginCrop()
        viewModel.updateCropDraft(CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5))

        viewModel.canvasState.resetForSource()

        XCTAssertEqual(viewModel.canvasState.navigation, CanvasNavigation())
        XCTAssertFalse(viewModel.canvasState.isCropToolActive)
        XCTAssertNil(viewModel.canvasState.cropDraft)
    }
}
