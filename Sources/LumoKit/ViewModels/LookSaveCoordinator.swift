import Foundation
import AppKit
import UniformTypeIdentifiers

/// Owns the active-photo “Save as Look/LUT” confirmation and save flow.
///
/// The coordinator snapshots the document and resolved Look when presented. Conversion and file
/// writing never call back into `AppViewModel`, so cancellation or failure cannot touch the active
/// document or its undo history. A successful save only publishes a file for the Look browser.
@MainActor
final class LookSaveCoordinator: ObservableObject {
    @Published var isSheetPresented = false
    @Published private(set) var isConverting = false
    @Published private(set) var conversion: LookLUTConversion?
    @Published var name = ""
    @Published private(set) var saveError: String?

    var onStatus: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onSaved: ((URL) -> Void)?
    var libraryFolder: (() -> URL?)?
    /// Canonical app-owned fallback used when the user has not selected an external Look folder.
    var canonicalLibraryFolder: (() -> URL?)?

    private var document = EditDocument()
    private var lut: CubeLUT?
    private var conversionTask: Task<Void, Never>?

    func present(document: EditDocument, lut: CubeLUT?, suggestedName: String = "Look") {
        conversionTask?.cancel()
        self.document = document
        self.lut = lut
        self.conversion = nil
        self.saveError = nil
        self.name = LookNameValidator.validate(suggestedName) ?? "Look"
        self.isSheetPresented = true
        self.isConverting = true

        conversionTask = Task { [document, lut] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try LookLUTConverter.convert(document: document, lut: lut)
                }.value
                guard !Task.isCancelled else { return }
                self.conversion = result
                self.isConverting = false
            } catch is CancellationError {
                // Dismissing the sheet is a normal user action, not an error.
            } catch {
                guard !Task.isCancelled else { return }
                self.isConverting = false
                self.saveError = error.localizedDescription
                self.onError?("Save Look failed: \(error.localizedDescription)")
            }
        }
    }

    func dismiss() {
        conversionTask?.cancel()
        conversionTask = nil
        isSheetPresented = false
        isConverting = false
    }

    /// Present the destination panel after the user has reviewed the support matrix.
    func saveDialog() {
        guard conversion != nil else { return }
        guard let validName = LookNameValidator.validate(name) else {
            saveError = "Enter a Look name without path separators or control characters."
            return
        }

        let panel = NSSavePanel()
        panel.title = "Save Look"
        panel.nameFieldStringValue = validName + ".cube"
        if let folder = libraryFolder?() ?? canonicalLibraryFolder?() { panel.directoryURL = folder }
        if let cubeType = UTType(filenameExtension: "cube") {
            panel.allowedContentTypes = [cubeType]
        }
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            try performSave(name: validName, to: destination)
            onStatus?("Saved Look: \(destination.lastPathComponent)")
            onSaved?(destination)
            dismiss()
        } catch {
            saveError = error.localizedDescription
            onError?("Save Look failed: \(error.localizedDescription)")
        }
    }

    /// Panel-free save seam used by automated coverage and by alternate UI surfaces.
    func performSave(name rawName: String, to destination: URL) throws {
        guard let conversion else { throw LookSaveError.notReady }
        guard let name = LookNameValidator.validate(rawName) else {
            throw LookSaveError.invalidName
        }
        guard destination.pathExtension.lowercased() == "cube" else {
            throw LookSaveError.invalidDestination
        }

        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue,
              fm.isWritableFile(atPath: parent.path) else {
            throw LookSaveError.invalidDestination
        }
        guard !fm.fileExists(atPath: destination.path) else {
            throw LookSaveError.nameCollision
        }

        do {
            try CubeLUT.write(text: conversion.cubeText(title: name), to: destination)
        } catch {
            throw LookSaveError.writeFailed(error.localizedDescription)
        }
    }

    enum LookSaveError: LocalizedError, Sendable {
        case notReady
        case invalidName
        case invalidDestination
        case nameCollision
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .notReady: return "The Look is still being prepared."
            case .invalidName: return "Enter a valid Look name."
            case .invalidDestination: return "Choose a writable folder and save the Look as a .cube file."
            case .nameCollision: return "A Look with that filename already exists. Choose a different name or destination."
            case .writeFailed(let detail): return "The Look could not be written: \(detail)"
            }
        }
    }

    /// Test seam for installing a precomputed conversion without presenting a panel.
    func setConversion(_ conversion: LookLUTConversion, name: String = "Look") {
        self.conversion = conversion
        self.name = name
        self.isConverting = false
        self.saveError = nil
    }
}
