import XCTest
@testable import LumoKit

@MainActor
final class LumoSettingsTests: TempDirectoryTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "LumoSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testAppearancePersistsAndUnrelatedSettingsSurvive() {
        let defaults = makeDefaults()
        defaults.set(["Info", "Look"], forKey: "lumo.inspector.tabs")
        let first = LumoSettings(preferences: defaults, userLookFolderURL: tempDirectory)

        XCTAssertFalse(first.alwaysDarkMode)
        first.alwaysDarkMode = true

        let relaunched = LumoSettings(preferences: defaults, userLookFolderURL: tempDirectory)
        XCTAssertTrue(relaunched.alwaysDarkMode)
        XCTAssertEqual(defaults.stringArray(forKey: "lumo.inspector.tabs"), ["Info", "Look"])
        XCTAssertEqual(defaults.integer(forKey: "Lumo.settings.schemaVersion"), 1)
    }

    func testSourceAndExportFoldersPersistIndependentlyAndReset() throws {
        let defaults = makeDefaults()
        let source = tempDirectory.appendingPathComponent("Imports")
        let export = tempDirectory.appendingPathComponent("Exports")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
        let settings = LumoSettings(preferences: defaults, userLookFolderURL: tempDirectory)

        XCTAssertTrue(settings.setDefaultFolder(source, for: .source))
        XCTAssertTrue(settings.setDefaultFolder(export, for: .export))
        XCTAssertEqual(settings.sourceFolderStatus.availability, .available)
        XCTAssertEqual(settings.exportFolderStatus.availability, .available)
        XCTAssertEqual(settings.defaultSourceFolderURL?.standardizedFileURL, source.standardizedFileURL)
        XCTAssertEqual(settings.testDefaultFolder(.export).status.availability, .available)

        let relaunched = LumoSettings(preferences: defaults, userLookFolderURL: tempDirectory)
        XCTAssertEqual(relaunched.defaultSourceFolderURL?.standardizedFileURL, source.standardizedFileURL)
        XCTAssertEqual(relaunched.defaultExportFolderURL?.standardizedFileURL, export.standardizedFileURL)

        relaunched.resetDefaultFolder(.source)
        XCTAssertNil(relaunched.defaultSourceFolderURL)
        XCTAssertEqual(relaunched.exportFolderStatus.availability, .available)
    }

    func testUnavailableFolderKeepsConfiguredPreferenceAndReportsRecovery() throws {
        let defaults = makeDefaults()
        let folder = tempDirectory.appendingPathComponent("Disconnected")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let settings = LumoSettings(preferences: defaults, userLookFolderURL: tempDirectory)
        XCTAssertTrue(settings.setDefaultFolder(folder, for: .source))

        try FileManager.default.removeItem(at: folder)
        settings.refreshFolderStatus()

        XCTAssertEqual(settings.sourceFolderStatus.availability, .unavailable)
        XCTAssertEqual(settings.sourceFolderStatus.displayName, "Disconnected")
        XCTAssertTrue(settings.testDefaultFolder(.source).message.contains("Choose it again"))

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertTrue(settings.setDefaultFolder(folder, for: .source))
        XCTAssertEqual(settings.sourceFolderStatus.availability, .available)
    }

    func testMigrationSeedsSourceDefaultWithoutReplacingWorkflowOrLookSettings() throws {
        let defaults = makeDefaults()
        let currentSource = tempDirectory.appendingPathComponent("Current Source")
        try FileManager.default.createDirectory(at: currentSource, withIntermediateDirectories: true)
        let bookmark = try currentSource.bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil
        )
        defaults.set(bookmark, forKey: "imageSourceFolderBookmark")
        defaults.set(Data("existing-look-bookmark".utf8), forKey: "lutFolderBookmark")
        defaults.set(true, forKey: "lumo.inspector.isPresented")

        let settings = LumoSettings(preferences: defaults, userLookFolderURL: tempDirectory)
        XCTAssertEqual(settings.defaultSourceFolderURL?.standardizedFileURL, currentSource.standardizedFileURL)
        XCTAssertEqual(defaults.data(forKey: "lutFolderBookmark"), Data("existing-look-bookmark".utf8))
        XCTAssertEqual(defaults.bool(forKey: "lumo.inspector.isPresented"), true)
        XCTAssertEqual(defaults.integer(forKey: "Lumo.settings.schemaVersion"), 1)
    }

    func testCanonicalUserLookFolderIsAppOwnedAndCreated() {
        let canonical = tempDirectory.appendingPathComponent("User Looks")
        let settings = LumoSettings(
            preferences: makeDefaults(), userLookFolderURL: canonical
        )

        XCTAssertEqual(settings.ensureUserLookFolder(), canonical)
        XCTAssertTrue(FileManager.default.fileExists(atPath: canonical.path))
        XCTAssertNil(settings.sourceFolderStatus.url)
    }
}
