import CoreGraphics
import Foundation

/// The committed, non-destructive crop framing.
///
/// The rectangle is expressed in the oriented source image's normalized coordinate space. Its
/// origin is bottom-left, matching Core Image and keeping the value independent of preview scale.
/// Rotation and aspect-ratio constraints are intentionally out of scope for this first crop tool;
/// freeform framing is the only interaction exposed by the editor.
struct CropAdjustments: Codable, Equatable, Sendable {
    static let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    static let neutral = CropAdjustments()

    var normalizedRect: CGRect? {
        didSet { normalizedRect = Self.normalized(normalizedRect) }
    }

    init(normalizedRect: CGRect? = nil) {
        self.normalizedRect = Self.normalized(normalizedRect)
    }

    var isIdentity: Bool {
        guard let normalizedRect else { return true }
        return normalizedRect == Self.unitRect
    }

    private enum CodingKeys: String, CodingKey {
        case normalizedRect
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        normalizedRect = Self.normalized(
            try container.decodeIfPresent(CGRect.self, forKey: .normalizedRect)
        )
    }

    private static func normalized(_ rect: CGRect?) -> CGRect? {
        guard let rect,
              rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.size.width.isFinite, rect.size.height.isFinite,
              rect.width > 0, rect.height > 0
        else { return nil }

        let clipped = rect.intersection(unitRect)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        return clipped
    }
}
