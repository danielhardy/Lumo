import XCTest
import CoreImage
@testable import LumoKit

@MainActor
final class PreviewSurfaceTests: XCTestCase {

    func testPresentStoresTheWorkingSpaceForThePresentedImage() {
        let surface = PreviewSurface()
        let image = CIImage(color: CIColor(red: 0.5, green: 0.25, blue: 0.75))

        surface.present(image, space: .displayP3)

        XCTAssertTrue(surface.image === image)
        XCTAssertEqual(surface.space, .displayP3)
    }

    func testClearResetsTheWorkingSpace() {
        let surface = PreviewSurface()
        surface.present(CIImage(color: .red), space: .displayP3)

        surface.clear()

        XCTAssertNil(surface.image)
        XCTAssertEqual(surface.space, .current)
    }

    func testHeadlessSurfaceConfirmsACompletedPresentationImmediately() {
        let surface = PreviewSurface()
        let telemetry = LiveEditTelemetry()
        let source = ImageSource(
            url: URL(fileURLWithPath: "/tmp/presentation-test.png"),
            nativeExtent: CGSize(width: 2, height: 2)
        )
        var confirmed = false

        surface.present(
            CIImage(color: .red), revision: 1, telemetry: telemetry, source: source,
            onPresented: { confirmed = true }
        )

        XCTAssertTrue(confirmed, "headless tests should not wait for a drawable that does not exist")
    }

    func testAFailedReplacementKeepsTheLastValidFrame() throws {
        let surface = PreviewSurface()
        let first = CIImage(color: .red)
        let replacement = CIImage(color: .blue)

        surface.present(first)
        let firstRevision = try XCTUnwrap(surface.pendingDisplayRevision())
        surface.markPresentationSucceeded(displayRevision: firstRevision)

        surface.present(replacement)
        let replacementRevision = try XCTUnwrap(surface.pendingDisplayRevision())
        surface.rejectPresentation(displayRevision: replacementRevision)

        XCTAssertTrue(surface.image === first)
        XCTAssertNil(surface.pendingDisplayRevision())
    }

    func testAStalePresentationCompletionCannotCommitOverANewerFrame() throws {
        let surface = PreviewSurface()
        let first = CIImage(color: .red)
        let second = CIImage(color: .green)

        surface.present(first)
        let firstRevision = try XCTUnwrap(surface.pendingDisplayRevision())
        surface.present(second)
        surface.markPresentationSucceeded(displayRevision: firstRevision)

        XCTAssertTrue(surface.image === second)
        XCTAssertNotNil(surface.pendingDisplayRevision())
    }

    func testNavigationCannotReplaceAValidSharperFrameWithALowerDetailFrame() throws {
        let surface = PreviewSurface()
        let identity = PreviewFrameIdentity(sourceToken: "source", documentHash: "document", space: .current)
        let sharp = CIImage(color: .red)
        let cheap = CIImage(color: .blue)

        surface.present(sharp, detailIdentity: identity, detailFactor: 1)
        let sharpRevision = try XCTUnwrap(surface.pendingDisplayRevision())
        surface.markPresentationSucceeded(displayRevision: sharpRevision)

        XCTAssertFalse(surface.present(cheap, detailIdentity: identity, detailFactor: 0.5))
        XCTAssertTrue(surface.image === sharp)
        XCTAssertNil(surface.pendingDisplayRevision())
    }
}
