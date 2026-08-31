import Foundation
import CoreImage

/// Actor-confined Core Image resource for the separable master RGB curve.
///
/// The kernel is compiled once and the curve is represented by one 256×1 texture (4 KiB), rather
/// than by a 64³ RGBA cube (4 MiB). `CIFilter`/`CIKernel`/`CIImage` are deliberately not Sendable;
/// the owning `RenderEngine` actor serializes access to this cache.
final class ToneCurveFilterCache {
    private static let sampleCount = 256
    private static let kernel = CIKernel(source: """
    kernel vec4 applyToneCurve(sampler image, sampler curve) {
        vec4 pixel = sample(image, samplerCoord(image));
        if (pixel.a <= 0.00001) { return pixel; }

        float red = sample(curve, vec2(clamp(pixel.r / pixel.a, 0.0, 1.0) * 255.0, 0.5)).r;
        float green = sample(curve, vec2(clamp(pixel.g / pixel.a, 0.0, 1.0) * 255.0, 0.5)).r;
        float blue = sample(curve, vec2(clamp(pixel.b / pixel.a, 0.0, 1.0) * 255.0, 0.5)).r;
        return vec4(vec3(red, green, blue) * pixel.a, pixel.a);
    }
    """)

    private var curve: LightToneCurve?
    private var sampledData: Data?
    private var sampledImage: CIImage?

    /// Applies the latest curve. Reusing the compiled kernel and replacing only this small texture
    /// makes curve ticks bounded by the sample count, not by the cube volume.
    func apply(_ nextCurve: LightToneCurve, to image: CIImage) -> CIImage {
        if curve != nextCurve || sampledImage == nil {
            var samples = [Float](repeating: 0, count: Self.sampleCount * 4)
            for index in 0..<Self.sampleCount {
                let value = Float(nextCurve.value(at: Double(index) / Double(Self.sampleCount - 1)))
                let offset = index * 4
                samples[offset] = value
                samples[offset + 1] = value
                samples[offset + 2] = value
                samples[offset + 3] = 1
            }
            sampledData = samples.withUnsafeBytes { Data($0) }
            sampledImage = sampledData.flatMap {
                CIImage(bitmapData: $0, bytesPerRow: Self.sampleCount * 4 * MemoryLayout<Float>.size,
                        size: CGSize(width: Self.sampleCount, height: 1), format: .RGBAf,
                        colorSpace: nil)
            }
            curve = nextCurve
        }

        guard let kernel = Self.kernel, let sampledImage else { return image }
        return kernel.apply(extent: image.extent, roiCallback: { _, rect in rect },
                            arguments: [image, sampledImage]) ?? image
    }

    /// Explicitly drops the texture when the source or working-space boundary is invalidated.
    func removeAll() {
        curve = nil
        sampledData = nil
        sampledImage = nil
    }

    var hasCachedCurve: Bool { sampledImage != nil }
}
