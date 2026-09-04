import Foundation

/// Value-only handoff from an import/open action to the source-session loader.
///
/// The plan resolves stable identity, backing storage, decoder kind, and persistence reference in
/// one place. It has no UI or asynchronous behavior, so URL-backed opens and Photos/data-backed
/// imports can test the same source contract without constructing `AppViewModel`.
struct SourceImportPlan: Sendable, Equatable {
    let name: String
    let url: URL?
    let data: Data?
    let assetID: PhotoAssetID
    let dataFingerprint: String?
    let traceQuality: String

    init(
        name: String,
        url: URL?,
        data: Data?,
        assetID: PhotoAssetID? = nil,
        dataFingerprint: String? = nil,
        traceQuality: String = "open"
    ) {
        self.name = name
        self.url = url
        self.data = data
        self.assetID = assetID
            ?? url.map(PhotoAssetID.file)
            ?? data.map(PhotoAssetID.data)
            ?? .data(Data())
        self.dataFingerprint = dataFingerprint
        self.traceQuality = traceQuality
    }

    var sourceReference: EditSourceReference {
        EditSourceReference(assetID: assetID, url: url)
    }

    var source: ImageSource {
        if let url {
            return ImageSource(url: url, nativeExtent: .zero)
        }
        if let data {
            return ImageSource(data: data, nativeExtent: .zero, dataFingerprint: dataFingerprint)
        }
        return ImageSource(backing: .data(Data()), kind: .standard, nativeExtent: .zero)
    }
}
