import XCTest
import AppKit
import SwiftUI
@testable import LumoKit

/// The Look inspector's visual states are intentionally represented by a small presentation
/// matrix. The hosting tests below render the shipping SwiftUI tree so width and accessibility
/// regressions are caught without adding a third-party snapshot dependency.
@MainActor
final class LookInspectorViewTests: XCTestCase {
    func testEmptyStatePresentationMatrix() {
        XCTAssertEqual(
            LookInspectorEmptyState.resolve(
                isScanning: true,
                lookCount: 0,
                folderConfigured: true,
                scanError: nil
            ),
            .scanning
        )
        XCTAssertEqual(
            LookInspectorEmptyState.resolve(
                isScanning: false,
                lookCount: 0,
                folderConfigured: true,
                scanError: "Can't find the selected folder"
            ),
            .folderUnavailable
        )
        XCTAssertEqual(
            LookInspectorEmptyState.resolve(
                isScanning: false,
                lookCount: 0,
                folderConfigured: true,
                scanError: nil,
                hasMissingReference: true
            ),
            .missingReference
        )
        XCTAssertEqual(
            LookInspectorEmptyState.resolve(
                isScanning: false,
                lookCount: 0,
                folderConfigured: true,
                scanError: nil
            ),
            .emptyFolder
        )
        XCTAssertEqual(
            LookInspectorEmptyState.resolve(
                isScanning: false,
                lookCount: 0,
                folderConfigured: false,
                scanError: nil
            ),
            .firstLook
        )
        XCTAssertEqual(
            LookInspectorEmptyState.resolve(
                isScanning: false,
                lookCount: 1,
                folderConfigured: true,
                scanError: nil
            ),
            .populated
        )
    }

    func testFirstLookCopyExplainsExternalSources() {
        let state = LookInspectorEmptyState.firstLook

        XCTAssertEqual(state.title, "Bring in your first Look")
        XCTAssertTrue(state.message.contains(".cube"))
        XCTAssertTrue(state.message.contains(".look"))
        XCTAssertTrue(state.message.contains("starter library"))
    }

    func testRenderedEmptyStateMatrixAtInspectorWidths() throws {
        let cases: [(LookInspectorEmptyState, (AppViewModel) -> Void)] = [
            (.firstLook, { _ in }),
            (.scanning, { viewModel in
                viewModel.library.isScanning = true
            }),
            (.folderUnavailable, { viewModel in
                viewModel.library.folderURL = URL(fileURLWithPath: "/missing/look-folder")
                viewModel.library.scanError = "Can't find the selected folder"
            }),
            (.missingReference, { viewModel in
                viewModel.updateDocument {
                    $0.lut.lutID = LUTID(raw: "/missing/Moved Look.cube")
                }
            }),
            (.emptyFolder, { viewModel in
                viewModel.library.folderURL = URL(fileURLWithPath: "/selected/looks")
            }),
        ]

        for (expectedState, configure) in cases {
            let viewModel = AppViewModel(engine: FakeRenderEngine())
            configure(viewModel)

            for width in [CGFloat(240), 280, 360] {
                let rendered = render(viewModel: viewModel, width: width)
                XCTAssertEqual(rendered.hosting.bounds.width, width, "\(expectedState) width")
                XCTAssertGreaterThan(rendered.hosting.fittingSize.height, 0, "\(expectedState) height")
                XCTAssertEqual(expectedState.accessibilityLabel, "Look inspector: \(expectedState.title)")
                assertRasterized(rendered.hosting, state: expectedState)
            }
        }
    }

    func testRenderedPopulatedStateAtInspectorWidths() throws {
        let viewModel = AppViewModel(engine: FakeRenderEngine())
        let look = CubeLUT(
            cube: Array(repeating: SIMD3<Float>(0.5, 0.5, 0.5), count: 8),
            size: 2,
            name: "Populated Look",
            category: "General"
        )
        viewModel.library.categories = [
            LUTLibrary.Category(id: "General", name: "General", luts: [look])
        ]
        viewModel.library.allLUTs = [look]

        for width in [CGFloat(240), 280, 360] {
            let rendered = render(viewModel: viewModel, width: width)
            XCTAssertEqual(rendered.hosting.bounds.width, width, "populated width")
            XCTAssertGreaterThan(rendered.hosting.fittingSize.height, 0, "populated height")
            XCTAssertEqual(LookInspectorEmptyState.populated.accessibilityLabel, "Look inspector: Looks")
            assertRasterized(rendered.hosting, state: .populated)
        }
    }

    private struct RenderedLookInspector {
        let hosting: NSHostingView<LookInspectorView>
        let window: NSWindow
    }

    private func render(viewModel: AppViewModel, width: CGFloat) -> RenderedLookInspector {
        let hosting = NSHostingView(rootView: LookInspectorView(viewModel: viewModel))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 800),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        hosting.frame = window.contentView?.bounds ?? .zero
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return RenderedLookInspector(hosting: hosting, window: window)
    }

    private func assertRasterized(
        _ hosting: NSHostingView<LookInspectorView>,
        state: LookInspectorEmptyState
    ) {
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return XCTFail("\(state) did not produce a bitmap representation")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        XCTAssertGreaterThan(bitmap.pixelsWide, 0, "\(state) rendered width")
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0, "\(state) rendered height")
    }
}
