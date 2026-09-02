import XCTest
@testable import LumoKit

@MainActor
final class FilmstripNavigationTests: TempDirectoryTestCase {
    func testAdjacentIndexFollowsFilteredDisplayOrder() {
        let visibleIndices = [1, 4, 7]

        XCTAssertEqual(
            FilmstripNavigation.adjacentIndex(
                in: visibleIndices, selectedIndex: 4, direction: .previous
            ),
            1
        )
        XCTAssertEqual(
            FilmstripNavigation.adjacentIndex(
                in: visibleIndices, selectedIndex: 4, direction: .next
            ),
            7
        )
    }

    func testAdjacentIndexStopsAtFilmstripEnds() {
        let visibleIndices = [1, 4, 7]

        XCTAssertNil(
            FilmstripNavigation.adjacentIndex(
                in: visibleIndices, selectedIndex: 1, direction: .previous
            )
        )
        XCTAssertNil(
            FilmstripNavigation.adjacentIndex(
                in: visibleIndices, selectedIndex: 7, direction: .next
            )
        )
    }

    func testRapidNavigationKeepsOnlyTheNewestPendingSource() async throws {
        let first = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "first.png", in: tempDirectory
        )
        let second = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "second.png", in: tempDirectory
        )
        let third = try Fixtures.writeGradientPNG(
            width: 16, height: 12, named: "third.png", in: tempDirectory
        )
        let engine = FakeRenderEngine()
        await engine.gateSourcePreparation()
        let viewModel = AppViewModel(engine: engine)

        viewModel.openImage(url: first)
        while await engine.sourcePreparationCount < 1 { await Task.yield() }
        viewModel.openImage(url: second)
        viewModel.openImage(url: third)

        await engine.releaseSourcePreparation()
        let deadline = Date().addingTimeInterval(2)
        while viewModel.sourceURL != third {
            if Date() > deadline { return XCTFail("the newest source did not finish loading") }
            await Task.yield()
        }

        let preparationCount = await engine.sourcePreparationCount
        XCTAssertEqual(preparationCount, 2,
                       "one active preparation plus the newest pending source is the bound")
        XCTAssertEqual(viewModel.sourceSize, CGSize(width: 16, height: 12))
    }
}
