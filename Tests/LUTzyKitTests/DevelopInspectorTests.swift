import XCTest
import CoreImage
@testable import LUTzyKit

/// Phase 2 Step 10a. The ship gate is "the inspector drives live re-render", which is a claim about
/// wiring, so most of this drives `FakeRenderEngine` and asserts on the requests it recorded.
@MainActor
final class DevelopInspectorTests: TempDirectoryTestCase {

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while await !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(description)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func openStandardImage(_ viewModel: AppViewModel) async throws {
        let url = try Fixtures.writeGradientPNG(width: 32, height: 24, named: "shot.png", in: tempDirectory)
        viewModel.openImage(url: url)
        try await waitUntil("the image to load") { viewModel.sourceImage != nil }
    }

    // MARK: - Probing

    func testCapabilitiesArePublishedAfterOpeningAnImage() async throws {
        // Not `.everythingSupported`: that value is also `FakeRenderEngine.stubbedCapabilities`'
        // own field default, so an `AppViewModel` that hardcoded `.everythingSupported` and never
        // called the engine would pass this test just as happily. This is the "wrote a value that
        // equals the default" weakness (docs/CODE_REVIEW.md §2) — use a distinctive value, with a
        // mixed set of flags and non-round seeds, so the test can only pass if the engine's answer
        // actually made it through.
        let distinctiveCapabilities = RAWCapabilities(
            isSharpnessSupported: true,
            isDetailSupported: true,
            isLocalToneMapSupported: false,
            asShotTemperature: 5842.2,
            asShotTint: 14.04
        )
        let fake = FakeRenderEngine()
        await fake.setStubbedCapabilities(distinctiveCapabilities)
        let viewModel = AppViewModel(engine: fake)
        XCTAssertNil(viewModel.rawCapabilities, "nothing open yet")

        try await openStandardImage(viewModel)
        try await waitUntil("capabilities to arrive") { viewModel.rawCapabilities != nil }

        XCTAssertEqual(viewModel.rawCapabilities, distinctiveCapabilities)
    }

    /// The probe costs ~25 ms. Paying that once per image is fine; paying it per render would put it
    /// on every frame of a slider drag.
    func testCapabilitiesAreProbedOncePerOpenAndNotPerRender() async throws {
        let fake = FakeRenderEngine()
        let viewModel = AppViewModel(engine: fake)
        try await openStandardImage(viewModel)
        try await waitUntil("capabilities to arrive") { viewModel.rawCapabilities != nil }

        let afterOpen = await fake.capabilityProbeCount
        XCTAssertEqual(afterOpen, 1, "one open, one probe")

        // Several renders, no new image.
        viewModel.updateDocument { $0.rawDevelop.exposure = 0.5 }
        viewModel.updateDocument { $0.rawDevelop.exposure = 0.6 }
        viewModel.selectLUT(TestImages.warmLUT())
        try await Task.sleep(for: .milliseconds(200))

        let afterRenders = await fake.capabilityProbeCount
        XCTAssertEqual(afterRenders, 1, "rendering must never re-probe")
    }

    /// A standard image has no develop stage, so the panel must have nothing to offer.
    func testCapabilitiesAreClearedForAnImageWithNoDevelopStage() async throws {
        let fake = FakeRenderEngine()
        await fake.setStubbedCapabilities(nil)
        let viewModel = AppViewModel(engine: fake)

        try await openStandardImage(viewModel)
        try await Task.sleep(for: .milliseconds(200))

        // `nil` alone is also `AppViewModel.rawCapabilities`' pre-open default, so on its own this
        // assertion cannot tell "the engine was consulted and answered nil" apart from "the engine
        // was never consulted at all." Assert the probe count too, so the test can only pass if the
        // engine actually ran.
        let probeCount = await fake.capabilityProbeCount
        XCTAssertEqual(probeCount, 1, "the engine must still be consulted even with no develop stage")
        XCTAssertNil(viewModel.rawCapabilities)
    }
}
