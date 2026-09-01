import CoreGraphics
import Foundation

/// The value copied by “Copy All Edits”.
///
/// The categories are intentionally separate even though the current renderer only has a small
/// adjustment enum and no crop stage yet. Keeping the clipboard's shape wider than today's document
/// means selective copy can later choose categories without replacing the clipboard schema or
/// teaching every caller how to split an `EditDocument`.
struct EditClipboardPayload: Codable, Sendable, Equatable {
    static let currentVersion = 1

    enum Category: String, Codable, CaseIterable, Hashable, Sendable {
        case light
        case color
        case effects
        case crop
        case lut
        case develop
    }

    /// A category's currently supported post-develop stages. Empty is meaningful: it says that the
    /// source had no edit in that category, so pasting the category clears that category on a target.
    struct AdjustmentCategory: Codable, Sendable, Equatable {
        var adjustments: [AdjustmentNode] = []
    }

    /// The crop stage copied as a normalized, non-destructive framing value.
    struct CropCategory: Codable, Sendable, Equatable {
        var normalizedRect: CGRect?
        var angle: Double

        static let neutral = CropCategory(normalizedRect: nil, angle: 0)

        init(normalizedRect: CGRect? = nil, angle: Double = 0) {
            self.normalizedRect = normalizedRect
            self.angle = angle
        }

        private enum CodingKeys: String, CodingKey {
            case normalizedRect, angle
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            normalizedRect = try container.decodeIfPresent(CGRect.self, forKey: .normalizedRect)
            angle = try container.decodeIfPresent(Double.self, forKey: .angle) ?? 0
        }
    }

    var version: Int = EditClipboardPayload.currentVersion
    var light = AdjustmentCategory()
    var color = AdjustmentCategory()
    var effects = AdjustmentCategory()
    /// Current photographer-facing stages. The adjustment arrays above preserve the original
    /// ordered-node clipboard shape for older documents and future selective-copy consumers.
    var lightAdjustments = LightAdjustments.neutral
    var colorAdjustments = ColorAdjustments.neutral
    var effectAdjustments = EffectsAdjustments.neutral
    var crop = CropCategory.neutral
    var lut = LUTSettings.none
    var develop = RAWDevelopSettings.neutral

    /// Whether explicit RAW settings should replace the destination's settings when both photos
    /// are RAW. The default is to copy explicit user edits; `nil` values remain decoder defaults and
    /// therefore never carry the source photo's as-shot seed to another photo.
    var developPolicy: DevelopPolicy = .copyExplicitSettings

    enum DevelopPolicy: String, Codable, Sendable {
        case copyExplicitSettings
        case preserveDestination
    }

    init(
        version: Int = EditClipboardPayload.currentVersion,
        light: AdjustmentCategory = AdjustmentCategory(),
        color: AdjustmentCategory = AdjustmentCategory(),
        effects: AdjustmentCategory = AdjustmentCategory(),
        crop: CropCategory = .neutral,
        lut: LUTSettings = .none,
        develop: RAWDevelopSettings = .neutral,
        developPolicy: DevelopPolicy = .copyExplicitSettings
    ) {
        self.version = version
        self.light = light
        self.color = color
        self.effects = effects
        self.crop = crop
        self.lut = lut
        self.develop = develop
        self.developPolicy = developPolicy
    }

    private enum CodingKeys: String, CodingKey {
        case version, light, color, effects, lightAdjustments, colorAdjustments, effectAdjustments,
             crop, lut, develop, developPolicy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        guard version <= Self.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Edit clipboard was saved by a newer version of Lumo (schema \(version); this build reads \(Self.currentVersion))."
            )
        }
        self.version = version
        self.light = try container.decodeIfPresent(AdjustmentCategory.self, forKey: .light) ?? .init()
        self.color = try container.decodeIfPresent(AdjustmentCategory.self, forKey: .color) ?? .init()
        self.effects = try container.decodeIfPresent(AdjustmentCategory.self, forKey: .effects) ?? .init()
        self.lightAdjustments = try container.decodeIfPresent(LightAdjustments.self, forKey: .lightAdjustments) ?? .neutral
        self.colorAdjustments = try container.decodeIfPresent(ColorAdjustments.self, forKey: .colorAdjustments) ?? .neutral
        self.effectAdjustments = try container.decodeIfPresent(EffectsAdjustments.self, forKey: .effectAdjustments) ?? .neutral
        self.crop = try container.decodeIfPresent(CropCategory.self, forKey: .crop) ?? .neutral
        self.lut = try container.decodeIfPresent(LUTSettings.self, forKey: .lut) ?? .none
        self.develop = try container.decodeIfPresent(RAWDevelopSettings.self, forKey: .develop) ?? .neutral
        self.developPolicy = try container.decodeIfPresent(DevelopPolicy.self, forKey: .developPolicy) ?? .copyExplicitSettings
    }

    init(document: EditDocument, developPolicy: DevelopPolicy = .copyExplicitSettings) {
        let lightSlots: Set<AdjustmentSlot> = [.exposure, .highlightShadow]
        self.init(
            light: AdjustmentCategory(adjustments: document.adjustments.filter {
                lightSlots.contains($0.slot)
            }.sorted { $0.slot < $1.slot }),
            color: AdjustmentCategory(adjustments: document.adjustments.filter {
                !lightSlots.contains($0.slot)
            }.sorted { $0.slot < $1.slot }),
            lut: document.lut,
            develop: document.rawDevelop,
            developPolicy: developPolicy
        )
        self.lightAdjustments = document.light
        self.colorAdjustments = document.color
        self.effectAdjustments = document.effects
        self.crop = CropCategory(normalizedRect: document.crop.normalizedRect)
    }

    /// Build a destination document from the selected categories. This API is deliberately present
    /// before the selective-copy UI: future callers can pass a subset without changing the payload.
    func applying(
        to destination: EditDocument,
        destinationIsRAW: Bool,
        categories: Set<Category> = Set(Category.allCases)
    ) -> EditDocument {
        var result = destination

        if categories.contains(.light) {
            result.light = lightAdjustments
            result.adjustments = replacing(
                in: result.adjustments,
                slots: [.exposure, .highlightShadow],
                with: light.adjustments
            )
        }
        if categories.contains(.color) {
            result.color = colorAdjustments
            result.adjustments = replacing(
                in: result.adjustments,
                slots: [.colorControls, .temperatureTint, .vibrance],
                with: color.adjustments
            )
        }
        if categories.contains(.effects) {
            result.effects = effectAdjustments
        }
        if categories.contains(.crop) {
            result.crop = CropAdjustments(normalizedRect: crop.normalizedRect)
        }
        if categories.contains(.lut) {
            result.lut = lut
        }
        if categories.contains(.develop), destinationIsRAW,
           developPolicy == .copyExplicitSettings {
            result.rawDevelop = develop
        }
        return result
    }

    private func replacing(
        in destination: [AdjustmentNode],
        slots: Set<AdjustmentSlot>,
        with copied: [AdjustmentNode]
    ) -> [AdjustmentNode] {
        (destination.filter { !slots.contains($0.slot) } + copied)
            .sorted { $0.slot < $1.slot }
    }
}

typealias EditClipboard = EditClipboardPayload
