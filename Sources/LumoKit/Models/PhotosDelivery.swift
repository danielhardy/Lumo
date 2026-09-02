import Foundation
import Photos

/// The user-facing states relevant to adding an export to Photos.
enum PhotosAuthorizationState: String, Codable, Sendable, Equatable {
    case notDetermined
    case restricted
    case denied
    case authorized
    case limited

    var recoveryMessage: String? {
        switch self {
        case .authorized:
            return nil
        case .notDetermined:
            return "Allow Lumo to add photos when macOS asks for Photos access, then retry."
        case .denied:
            return "Photos access is denied. Enable Lumo in System Settings > Privacy & Security > Photos, then retry."
        case .restricted:
            return "Photos access is restricted by macOS or device policy and cannot be changed in Lumo."
        case .limited:
            return "Photos access is limited. Allow full access in System Settings > Privacy & Security > Photos to retry album delivery."
        }
    }
}

/// A policy for the optional post-export Photos delivery. It carries no PhotoKit objects.
struct PhotosExportOptions: Codable, Sendable, Equatable {
    /// An empty or whitespace-only name means “add to the library without an album”.
    let albumName: String?

    init(albumName: String? = nil) {
        let trimmed = albumName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.albumName = trimmed?.isEmpty == true ? nil : trimmed
    }
}

/// Album placement is optional, so an asset can be saved even if its album cannot be updated.
struct PhotosDeliveryResult: Sendable, Equatable {
    let assetAdded: Bool
    let albumAdded: Bool
    let warning: String?

    init(assetAdded: Bool = true, albumAdded: Bool = false, warning: String? = nil) {
        self.assetAdded = assetAdded
        self.albumAdded = albumAdded
        self.warning = warning
    }
}

enum PhotosDeliveryError: LocalizedError, Sendable, Equatable {
    case authorization(PhotosAuthorizationState)
    case libraryUnavailable(String)
    case assetCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .authorization(let state):
            return state.recoveryMessage ?? "Photos access is not available."
        case .libraryUnavailable(let reason):
            return "The Photos library is unavailable: \(reason)"
        case .assetCreationFailed(let reason):
            return "Photos could not add the export: \(reason)"
        }
    }
}

/// The seam used by the export coordinator. Tests can provide a fake without Photos authorization.
@MainActor
protocol PhotosDelivering {
    func deliver(
        data: Data,
        filename: String,
        format: ExportFormat,
        options: PhotosExportOptions
    ) async throws -> PhotosDeliveryResult
}

/// Production PhotoKit adapter. It is called only after the file export has committed.
@MainActor
final class PhotoKitDelivery: PhotosDelivering {
    private let library: PHPhotoLibrary

    init(library: PHPhotoLibrary = .shared()) {
        self.library = library
    }

    func deliver(
        data: Data,
        filename: String,
        format: ExportFormat,
        options: PhotosExportOptions
    ) async throws -> PhotosDeliveryResult {
        let authorization = await authorizationState(requestIfNeeded: true)
        guard authorization == .authorized || authorization == .limited else {
            throw PhotosDeliveryError.authorization(authorization)
        }
        if let reason = library.unavailabilityReason {
            throw PhotosDeliveryError.libraryUnavailable(reason.localizedDescription)
        }

        let assetIdentifier: String
        do {
            assetIdentifier = try await createAsset(data: data, filename: filename, format: format)
        } catch {
            throw PhotosDeliveryError.assetCreationFailed(error.localizedDescription)
        }

        guard let albumName = options.albumName else {
            return PhotosDeliveryResult(assetAdded: true)
        }

        do {
            try await addAsset(withIdentifier: assetIdentifier, toAlbumNamed: albumName)
            return PhotosDeliveryResult(assetAdded: true, albumAdded: true)
        } catch {
            // The asset transaction has already committed. Album placement is optional and must
            // not turn a successful Photos save into a total failure.
            return PhotosDeliveryResult(
                assetAdded: true,
                warning: "Added to Photos, but album \"\(albumName)\" could not be updated: \(error.localizedDescription)"
            )
        }
    }

    private func authorizationState(requestIfNeeded: Bool) async -> PhotosAuthorizationState {
        let current = Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        guard current == .notDetermined, requestIfNeeded else { return current }
        return Self.map(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    }

    private func createAsset(data: Data, filename: String, format: ExportFormat) async throws -> String {
        var identifier: String?
        try await library.performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let resourceOptions = PHAssetResourceCreationOptions()
            resourceOptions.originalFilename = filename
            resourceOptions.uniformTypeIdentifier = format.utType.identifier
            request.addResource(with: .photo, data: data, options: resourceOptions)
            identifier = request.placeholderForCreatedAsset?.localIdentifier
        }
        guard let identifier, !identifier.isEmpty else {
            throw PhotosDeliveryError.assetCreationFailed("Photos did not return an asset identifier.")
        }
        return identifier
    }

    private func addAsset(withIdentifier identifier: String, toAlbumNamed name: String) async throws {
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .albumRegular, options: nil
        )
        var existing: PHAssetCollection?
        collections.enumerateObjects { collection, _, stop in
            guard collection.localizedTitle == name else { return }
            existing = collection
            stop.pointee = true
        }
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier], options: nil
        ).firstObject else {
            throw PhotosDeliveryError.libraryUnavailable("the new asset could not be fetched")
        }

        if let existing {
            guard let change = PHAssetCollectionChangeRequest(for: existing) else {
                throw PhotosDeliveryError.libraryUnavailable("the album cannot be edited")
            }
            try await library.performChanges {
                change.addAssets(NSArray(object: asset))
            }
        } else {
            let creation = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(
                withTitle: name
            )
            try await library.performChanges {
                creation.addAssets(NSArray(object: asset))
            }
        }
    }

    private static func map(_ status: PHAuthorizationStatus) -> PhotosAuthorizationState {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        case .limited: return .limited
        @unknown default: return .denied
        }
    }
}
