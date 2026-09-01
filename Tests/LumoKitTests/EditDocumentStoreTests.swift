import Foundation
import XCTest
@testable import LumoKit

final class EditDocumentStoreTests: TempDirectoryTestCase {

    private func makeStore() -> (EditDocumentStore, URL) {
        let url = tempDirectory.appendingPathComponent("edit-records.json")
        return (EditDocumentStore(fileURL: url), url)
    }

    private func source(named name: String = "photo.jpg") -> EditSourceReference {
        let url = tempDirectory.appendingPathComponent(name)
        return EditSourceReference(assetID: .file(url), url: url)
    }

    private var editedDocument: EditDocument {
        EditDocument(
            rawDevelop: RAWDevelopSettings(exposure: 0.75),
            adjustments: [.exposure(ev: 0.4)],
            lut: .none
        )
    }

    func testRoundTripUsesASeparateJSONRecordAndLeavesSourceUntouched() async throws {
        let (store, fileURL) = makeStore()
        let source = source()
        let original = Data("source bytes stay source bytes".utf8)
        try original.write(to: try XCTUnwrap(source.url))

        try await store.save(editedDocument, for: source)
        let result = await store.load(for: source)

        XCTAssertTrue(result.found)
        XCTAssertEqual(result.document, editedDocument)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(source.url)), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(
            String(decoding: try Data(contentsOf: fileURL), as: UTF8.self).contains("\"schemaVersion\"")
        )
    }

    func testASecondWriteKeepsThePreviousPrimaryAsLastKnownGoodBackup() async throws {
        let (store, fileURL) = makeStore()
        let source = source()
        let first = EditDocument(adjustments: [.exposure(ev: 0.1)])
        let second = EditDocument(adjustments: [.exposure(ev: 0.9)])

        try await store.save(first, for: source)
        try await store.save(second, for: source)

        let backupURL = fileURL.appendingPathExtension("bak")
        let backupStore = EditDocumentStore(fileURL: backupURL)
        let backupResult = await backupStore.load(for: source)
        XCTAssertEqual(backupResult.document, first)
    }

    func testCorruptPrimaryRecoversTheLastKnownGoodDocument() async throws {
        let (store, fileURL) = makeStore()
        let source = source()
        let expected = editedDocument
        try await store.save(expected, for: source)
        try await store.save(EditDocument(adjustments: [.vibrance(amount: 0.2)]), for: source)

        try Data("{\"schemaVersion\":1,\"records\":".utf8).write(to: fileURL)

        let recovered = EditDocumentStore(fileURL: fileURL)
        let result = await recovered.load(for: source)
        XCTAssertEqual(result.document, expected)
        XCTAssertEqual(result.status, .recoveredFromBackup)
        XCTAssertTrue(result.status.message?.contains("last known-good") == true)
    }

    func testMalformedStoreFailsSafeWithActionableStatusAndDoesNotInventEdits() async throws {
        let (store, fileURL) = makeStore()
        try Data("partially written".utf8).write(to: fileURL)

        let result = await store.load(for: source())
        XCTAssertFalse(result.found)
        XCTAssertTrue(result.document.isIdentity)
        guard case .corrupt = result.status else {
            return XCTFail("expected malformed JSON to be reported as corrupt")
        }
        XCTAssertTrue(result.status.message?.contains("neutral edits") == true)
    }

    func testUnsupportedStoreVersionIsRejectedWithoutAllowingOverwrite() async throws {
        let (store, fileURL) = makeStore()
        let futureJSON = #"{"schemaVersion":99,"records":{}}"#
        try futureJSON.data(using: .utf8)!.write(to: fileURL)

        let result = await store.load(for: source())
        XCTAssertEqual(result.status, .unsupportedVersion(99))
        do {
            try await store.save(editedDocument, for: source())
            XCTFail("a newer store must not be overwritten")
        } catch {
            XCTAssertEqual(error as? EditDocumentStore.StoreError, .newerSchema(99))
        }
        XCTAssertEqual(
            try String(contentsOf: fileURL, encoding: .utf8),
            futureJSON
        )
    }

    func testLegacyBareMapMigratesOnTheNextWrite() async throws {
        let (store, fileURL) = makeStore()
        let source = source()
        let legacy: [String: EditDocument] = [source.assetID.description: editedDocument]
        try JSONEncoder().encode(legacy).write(to: fileURL)

        let result = await store.load(for: source)
        XCTAssertEqual(result.document, editedDocument)
        XCTAssertEqual(result.status, .migrated(from: 0))

        try await store.save(result.document, for: source)
        let canonical = try JSONDecoder().decode(
            [String: JSONValue].self,
            from: try Data(contentsOf: fileURL)
        )
        XCTAssertNotNil(canonical["schemaVersion"])
        XCTAssertNotNil(canonical["records"])
    }

    func testMovedFileRelinksByBookmarkAndRekeysTheRecord() async throws {
        let (store, _) = makeStore()
        let oldURL = tempDirectory.appendingPathComponent("old.jpg")
        let newURL = tempDirectory.appendingPathComponent("new.jpg")
        try Data("photo".utf8).write(to: oldURL)
        let oldSource = EditSourceReference(assetID: .file(oldURL), url: oldURL)
        try await store.save(editedDocument, for: oldSource)
        try FileManager.default.moveItem(at: oldURL, to: newURL)

        let result = await store.load(for: EditSourceReference(assetID: .file(newURL), url: newURL))
        XCTAssertEqual(result.document, editedDocument)
        XCTAssertEqual(result.status, .relinked)

        let relaunch = EditDocumentStore(fileURL: tempDirectory.appendingPathComponent("edit-records.json"))
        let relaunched = await relaunch.load(
            for: EditSourceReference(assetID: .file(newURL), url: newURL)
        )
        XCTAssertEqual(relaunched.document, editedDocument)
    }

    func testPersistenceIORunsOffTheMainActor() async throws {
        let (store, _) = makeStore()
        _ = await store.load(for: source())
        let didRunOnMainThread = await store.lastIOWasMainThread
        XCTAssertFalse(didRunOnMainThread)
    }

    func testFailingStoreCanRetryTheCompleteSnapshot() async throws {
        let url = tempDirectory.appendingPathComponent("failing-edits.json")
        let store = EditDocumentStore(fileURL: url, failuresBeforeSuccess: 1)
        let source = source()

        do {
            try await store.save(editedDocument, for: source)
            XCTFail("the injected failure should be surfaced")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("injected persistence failure"))
        }
        let failedWriteCount = await store.writeCount
        let failedAttemptCount = await store.saveAttemptCount
        XCTAssertEqual(failedWriteCount, 0)
        XCTAssertEqual(failedAttemptCount, 1)

        try await store.save(editedDocument, for: source)
        let restored = EditDocumentStore(fileURL: url)
        let result = await restored.load(for: source)
        XCTAssertEqual(result.document, editedDocument)
    }
}
/// Small JSON inspection value used only to assert the outer migration envelope without depending on
/// the store's private implementation types.
private enum JSONValue: Decodable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }
}
