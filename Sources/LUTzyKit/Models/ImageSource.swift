import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// How to *reproduce* the source image, rather than the image itself.
///
/// A RAW has to be re-developed from scratch on every render — `CIRAWFilter` is configured before it
/// produces an image, so there is no developed `CIImage` to hold on to and adjust. The pipeline
/// therefore needs the bytes, not a picture.
///
/// It is also the reason this type carries a URL or `Data` and never a live `CIImage`: `CIImage` is
/// not `Sendable`, and the whole point of the value-state spine is that nothing non-`Sendable` enters
/// app state. See `docs/PHASE2_SPEC.md` §4.2 and §4.5.
struct ImageSource: Sendable, Equatable {

    /// Where the bytes are.
    ///
    /// `.data` is not an afterthought: a Photos import arrives as bytes with **no URL at all**
    /// (`ImageCollection.Item.url` is `nil` for one). Writing those to a temp file to get a URL would
    /// mean inventing a filename, and extension-based RAW detection would then classify the file by
    /// whatever extension was guessed — plus someone has to delete it afterwards. Carrying the bytes
    /// avoids both.
    ///
    /// Note `Equatable` on `.data` compares the whole buffer. Sources are compared rarely (has the
    /// user opened a different image?), never per render, so that is the right trade — but it is a
    /// reason not to put an `ImageSource` inside a value that *is* compared per frame.
    enum Backing: Sendable, Equatable {
        case url(URL)
        case data(Data)
    }

    /// Which decode path the source needs. RAW goes through `CIRAWFilter` and honours
    /// `RAWDevelopSettings`; standard images do not.
    enum Kind: Sendable, Equatable {
        case raw
        case standard
    }

    let backing: Backing
    let kind: Kind
    /// The source's full pixel dimensions, upright. Lets `RenderScale` compute a downscale factor
    /// without decoding the image again.
    let nativeExtent: CGSize

    init(backing: Backing, kind: Kind, nativeExtent: CGSize) {
        self.backing = backing
        self.kind = kind
        self.nativeExtent = nativeExtent
    }

    /// A file-backed source, classified by extension — the same rule `ImageDecoder.load` uses,
    /// so a file cannot be RAW for one and standard for the other.
    init(url: URL, nativeExtent: CGSize) {
        self.init(backing: .url(url), kind: Self.kind(forExtension: url.pathExtension), nativeExtent: nativeExtent)
    }

    /// A bytes-backed source, classified by **content**.
    ///
    /// There is no filename to inspect here, so the UTI ImageIO reports for the buffer decides. This
    /// is what makes a RAW dropped in as a payload — or a Photos item delivered as one — take the
    /// RAW path rather than being misread as a standard image.
    init(data: Data, nativeExtent: CGSize) {
        self.init(backing: .data(data), kind: Self.kind(forData: data), nativeExtent: nativeExtent)
    }

    // MARK: - Classification

    static func kind(forExtension ext: String) -> Kind {
        ImageDecoder.rawExtensions.contains(ext.lowercased()) ? .raw : .standard
    }

    /// Classify a buffer by the type ImageIO reports for it. Anything undecodable or unrecognised is
    /// treated as standard: the standard path fails with a plain "cannot load" message, whereas
    /// pushing a non-RAW through `CIRAWFilter` fails less legibly.
    static func kind(forData data: Data) -> Kind {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let uti = CGImageSourceGetType(source),
              let type = UTType(uti as String)
        else { return .standard }
        return type.conforms(to: .rawImage) ? .raw : .standard
    }
}
