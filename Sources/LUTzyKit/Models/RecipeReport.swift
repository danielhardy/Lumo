import Foundation

/// Summary of what the recipe extractor learned about a (RAW, JPG) pair.
/// Drives the report card shown in the Derive sheet.
struct RecipeReport: Equatable {

    /// One bin of the per-channel tone curve. `input` is 0…1 luma in the
    /// neutral baseline render; `outputR/G/B` are the mean JPG values that
    /// fell into that luma bin.
    struct ToneCurvePoint: Equatable {
        let input: Float
        let outputR: Float
        let outputG: Float
        let outputB: Float
    }

    /// Camera info pulled from EXIF for the report card. ImageIO doesn't
    /// know how to decode Ricoh maker notes, so the proprietary "Image
    /// Control" name doesn't show up here — that's a separate phase-2 job.
    struct CameraInfo: Equatable {
        let make: String
        let model: String
        let software: String?
        let exifContrast: String?
        let exifSaturation: String?
        let exifSharpness: String?
        let exifWhiteBalance: String?
        let exifCustomRendered: String?
    }

    let toneCurve: [ToneCurvePoint]

    /// Mean JPG chroma divided by mean neutral chroma in smooth regions.
    /// 1.0 = no change; >1 = more saturated; <1 = more muted.
    let saturationRatio: Float

    /// High-frequency energy ratio (jpg / neutral). Captures sharpening
    /// strength. NOT encoded in the LUT — flagged in the report so the user
    /// knows to apply it separately if they want to match the camera.
    let sharpeningRatio: Float

    /// Number of smooth-region samples that survived the edge mask.
    let sampleCount: Int

    /// Percentage of cube cells that received at least one direct sample
    /// (the rest were filled by neighbor smoothing or anchored to identity).
    let cubeCoveragePercent: Float

    /// Integer-pixel shift detected between the JPG and the neutral render
    /// (positive = JPG is shifted that many pixels down/right). Usually
    /// near-zero; non-zero indicates a crop margin difference.
    let alignmentShift: (dx: Int, dy: Int)

    let cameraInfo: CameraInfo?

    static func == (lhs: RecipeReport, rhs: RecipeReport) -> Bool {
        lhs.toneCurve == rhs.toneCurve &&
        lhs.saturationRatio == rhs.saturationRatio &&
        lhs.sharpeningRatio == rhs.sharpeningRatio &&
        lhs.sampleCount == rhs.sampleCount &&
        lhs.cubeCoveragePercent == rhs.cubeCoveragePercent &&
        lhs.alignmentShift.dx == rhs.alignmentShift.dx &&
        lhs.alignmentShift.dy == rhs.alignmentShift.dy &&
        lhs.cameraInfo == rhs.cameraInfo
    }
}
