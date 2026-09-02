import CoreGraphics
import Foundation

/// The crop ratios exposed by the editor.
///
/// Presets are named in their conventional photographer-facing orientation. On a portrait source
/// a non-square preset uses its reciprocal pixel ratio, so choosing 3:2 produces a portrait 2:3
/// frame while keeping the same long-edge convention as a landscape source.
enum CropAspectRatio: String, Codable, CaseIterable, Hashable, Sendable {
    case freeform = "Freeform"
    case square = "1:1"
    case threeToTwo = "3:2"
    case fourToThree = "4:3"
    case sixteenToNine = "16:9"

    var label: String { rawValue }

    var isFreeform: Bool { self == .freeform }

    private var landscapePixelRatio: CGFloat? {
        switch self {
        case .freeform: return nil
        case .square: return 1
        case .threeToTwo: return 3.0 / 2.0
        case .fourToThree: return 4.0 / 3.0
        case .sixteenToNine: return 16.0 / 9.0
        }
    }

    /// The width-to-height ratio in normalized source coordinates. Normalization is necessary
    /// because a 1:1 rectangle in a 3:2 image has a normalized width-to-height ratio of 2:3.
    func normalizedRatio(for imageSize: CGSize) -> CGFloat? {
        guard let landscapePixelRatio = landscapePixelRatio,
              imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0
        else { return nil }

        let pixelRatio = imageSize.width < imageSize.height
            ? 1 / landscapePixelRatio
            : landscapePixelRatio
        let normalizedRatio = pixelRatio * imageSize.height / imageSize.width
        guard normalizedRatio.isFinite, normalizedRatio > 0 else { return nil }
        return normalizedRatio
    }
}

/// The committed, non-destructive crop framing.
///
/// The rectangle is expressed in the oriented source image's normalized coordinate space. Its
/// origin is bottom-left, matching Core Image and keeping the value independent of preview scale.
/// The selected aspect ratio is persisted alongside the rectangle so reopening the crop tool,
/// undoing, or exporting never loses the user's framing constraint.
struct CropAdjustments: Codable, Equatable, Sendable {
    static let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    static let neutral = CropAdjustments()

    var normalizedRect: CGRect? {
        didSet { normalizedRect = Self.normalized(normalizedRect) }
    }

    var aspectRatio: CropAspectRatio

    init(normalizedRect: CGRect? = nil, aspectRatio: CropAspectRatio = .freeform) {
        self.normalizedRect = Self.normalized(normalizedRect)
        self.aspectRatio = aspectRatio
    }

    var isIdentity: Bool {
        guard let normalizedRect else { return aspectRatio.isFreeform }
        return normalizedRect == Self.unitRect && aspectRatio.isFreeform
    }

    private enum CodingKeys: String, CodingKey {
        case normalizedRect, aspectRatio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        normalizedRect = Self.normalized(
            try container.decodeIfPresent(CGRect.self, forKey: .normalizedRect)
        )
        aspectRatio = try container.decodeIfPresent(CropAspectRatio.self, forKey: .aspectRatio) ?? .freeform
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

/// Pure crop geometry shared by the SwiftUI overlay and model tests.
enum CropOverlayInteraction {
    static func applying(
        _ aspectRatio: CropAspectRatio, to rect: CGRect, imageSize: CGSize
    ) -> CGRect {
        guard let targetRatio = aspectRatio.normalizedRatio(for: imageSize),
              let current = CropAdjustments(normalizedRect: rect).normalizedRect
        else { return rect }

        // Preserve the current crop area and center wherever possible. Scaling both dimensions
        // from the current area avoids an aspect-ratio change unexpectedly zooming the subject.
        let area = current.width * current.height
        var width = sqrt(area * targetRatio)
        var height = width / targetRatio
        let scale = min(1 / width, 1 / height)
        if scale < 1 {
            width *= scale
            height *= scale
        }
        return centeredRect(width: width, height: height, around: current.center)
    }

    static func translated(_ rect: CGRect, delta: CGSize, imageRect: CGRect) -> CGRect {
        guard imageRect.width > 0, imageRect.height > 0 else { return rect }
        let dx = delta.width / imageRect.width
        let dy = -delta.height / imageRect.height
        return rect.offsetBy(
            dx: min(max(dx, -rect.minX), 1 - rect.maxX),
            dy: min(max(dy, -rect.minY), 1 - rect.maxY)
        )
    }

    static func resized(
        _ rect: CGRect,
        handle: CropHandle,
        delta: CGSize,
        imageRect: CGRect,
        aspectRatio: CropAspectRatio = .freeform,
        imageSize: CGSize = .zero
    ) -> CGRect {
        guard imageRect.width > 0, imageRect.height > 0 else { return rect }
        guard let targetRatio = aspectRatio.normalizedRatio(for: imageSize) else {
            return freeformResized(rect, handle: handle, delta: delta, imageRect: imageRect)
        }

        let dx = delta.width / imageRect.width
        let dy = -delta.height / imageRect.height
        let anchor: CGPoint
        let target: CGPoint
        let horizontalDirection: CGFloat
        let verticalDirection: CGFloat

        switch handle {
        case .topLeading:
            anchor = CGPoint(x: rect.maxX, y: rect.minY)
            target = CGPoint(x: rect.minX + dx, y: rect.maxY + dy)
            horizontalDirection = -1
            verticalDirection = 1
        case .topTrailing:
            anchor = CGPoint(x: rect.minX, y: rect.minY)
            target = CGPoint(x: rect.maxX + dx, y: rect.maxY + dy)
            horizontalDirection = 1
            verticalDirection = 1
        case .bottomLeading:
            anchor = CGPoint(x: rect.maxX, y: rect.maxY)
            target = CGPoint(x: rect.minX + dx, y: rect.minY + dy)
            horizontalDirection = -1
            verticalDirection = -1
        case .bottomTrailing:
            anchor = CGPoint(x: rect.minX, y: rect.maxY)
            target = CGPoint(x: rect.maxX + dx, y: rect.minY + dy)
            horizontalDirection = 1
            verticalDirection = -1
        }

        let requestedWidth = abs(target.x - anchor.x)
        let requestedHeight = abs(target.y - anchor.y)
        var width = max(requestedWidth, requestedHeight * targetRatio)
        let maxWidth = horizontalDirection > 0 ? 1 - anchor.x : anchor.x
        let maxHeight = verticalDirection > 0 ? 1 - anchor.y : anchor.y
        let maximumWidth = min(maxWidth, maxHeight * targetRatio)
        let minimumWidth = min(maximumWidth, max(0.04, 0.04 * targetRatio))
        width = min(max(width, minimumWidth), maximumWidth)
        let height = width / targetRatio

        let minX = horizontalDirection > 0 ? anchor.x : anchor.x - width
        let minY = verticalDirection > 0 ? anchor.y : anchor.y - height
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    private static func freeformResized(
        _ rect: CGRect, handle: CropHandle, delta: CGSize, imageRect: CGRect
    ) -> CGRect {
        let dx = delta.width / imageRect.width
        let dy = -delta.height / imageRect.height
        let minimum: CGFloat = 0.04
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY

        switch handle {
        case .topLeading:
            minX = min(max(rect.minX + dx, 0), rect.maxX - minimum)
            maxY = min(max(rect.maxY + dy, rect.minY + minimum), 1)
        case .topTrailing:
            maxX = min(max(rect.maxX + dx, rect.minX + minimum), 1)
            maxY = min(max(rect.maxY + dy, rect.minY + minimum), 1)
        case .bottomLeading:
            minX = min(max(rect.minX + dx, 0), rect.maxX - minimum)
            minY = min(max(rect.minY + dy, 0), rect.maxY - minimum)
        case .bottomTrailing:
            maxX = min(max(rect.maxX + dx, rect.minX + minimum), 1)
            minY = min(max(rect.minY + dy, 0), rect.maxY - minimum)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func centeredRect(width: CGFloat, height: CGFloat, around center: CGPoint) -> CGRect {
        CGRect(
            x: min(max(center.x - width / 2, 0), 1 - width),
            y: min(max(center.y - height / 2, 0), 1 - height),
            width: width,
            height: height
        )
    }
}

enum CropHandle: CaseIterable, Hashable, Sendable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
