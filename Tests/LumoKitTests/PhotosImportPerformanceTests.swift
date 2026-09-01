import XCTest
@testable import LumoKit

/// Opt-in timing harness for a real camera RAW. The repository intentionally does not carry a
/// multi-dozen-megapixel sample, so this test never turns the absence of a licensed local RAW into
/// a CI failure. Its output is the before/after report used with Instruments on a reference Mac.
@MainActor
final class PhotosImportPerformanceTests: XCTestCase {

    func testProfileOneLargeRAWImportBeforeAndAfter() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LUMO_PHOTOS_BENCHMARK"] != nil,
            "set LUMO_PHOTOS_BENCHMARK=1 to run the Photos import timing harness"
        )
        guard let path = ProcessInfo.processInfo.environment["LUMO_PHOTOS_RAW"] else {
            throw XCTSkip("set LUMO_PHOTOS_RAW to a representative 40–60 MP RAW")
        }
        let url = URL(fileURLWithPath: path)
        guard let sourceData = try? Data(contentsOf: url) else {
            throw XCTSkip("could not read LUMO_PHOTOS_RAW")
        }

        // The old path's transfer proxy reads every payload before insertion, retaining all of
        // them in a temporary array. The new path appends each payload as soon as it transfers.
        let oldTransfer = elapsed {
            _ = try? Data(contentsOf: url)
            _ = try? Data(contentsOf: url)
            _ = try? Data(contentsOf: url)
        }
        let newTransfer = elapsed {
            for _ in 0..<3 { _ = try? Data(contentsOf: url) }
        }

        let decode = elapsed {
            _ = try? ImageDecoder.load(from: sourceData, name: url.lastPathComponent,
                                       traceQuality: "photosImport")
        }
        let thumbnail = elapsed {
            _ = Thumbnails.generate(from: sourceData)
        }

        let oldCollection = ImageCollection()
        let oldInsertion = elapsed {
            oldCollection.addFromData((0..<3).map {
                (name: "Photo \($0 + 1)", data: sourceData)
            })
        }

        let newCollection = ImageCollection()
        let newInsertion = elapsed {
            newCollection.beginDataImport()
            for ordinal in 0..<3 {
                _ = newCollection.appendDataImport(
                    ImageCollection.PhotoImportItem(
                        name: "Photo \(ordinal + 1)", data: sourceData,
                        localIdentifier: "benchmark.\(ordinal)"
                    ),
                    ordinal: ordinal
                )
            }
            newCollection.finishDataImport()
        }

        print("""
        PHOTOS_IMPORT_PROFILE
          source_bytes=\(sourceData.count) path=\(url.lastPathComponent)
          before_transfer_ms=\(oldTransfer)
          after_transfer_ms=\(newTransfer)
          decode_ms=\(decode)
          thumbnail_ms=\(thumbnail)
          before_collection_insert_ms=\(oldInsertion)
          after_collection_insert_ms=\(newInsertion)
          selection_count=3
        """)
    }

    private func elapsed(_ work: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        work()
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000
    }
}
