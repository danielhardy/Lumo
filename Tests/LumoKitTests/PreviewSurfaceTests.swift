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
}
