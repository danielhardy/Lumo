import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// Turns an `EditDocument` into one lazy `CIImage`. A pure function — no `CIContext`, no rasterizing,
/// no state.
///
/// This is the middle layer of Phase 2: the document describes the look, this folds it into a filter
/// graph, and `actor RenderEngine` (Step 4) evaluates that graph at one of two scales. **Preview and
/// export call this same function and differ only in `scale`**, which is what makes their agreement
/// structural rather than a coincidence that two code paths currently maintain. See
/// `docs/PHASE2_SPEC.md` §1 and §3.
///
/// Nothing here is rasterized. Every stage hands the next a lazy `CIImage`, so the whole chain costs
/// one GPU pass when the engine finally renders it.
enum RenderPipeline {

    /// Increment whenever the pixels produced by the graph can change without a cache-key input
    /// changing. This makes cache invalidation explicit when the pipeline evolves.
    /// v2 added the Light stage to the graph. v3 refines its non-neutral mapping to the native EV
    /// plus tonal-curve implementation. v4 clamps the tone curve's interior points to stay
    /// monotonic; some Contrast/Highlights/Shadows combinations previously produced a curve that
    /// inverted tones locally, so affected documents render different pixels even though the
    /// document schema is unchanged. v5 adds the Whites and Blacks endpoint stages. v6 adds the
    /// editable master RGB curve. v7 adds the global Color stage. v8 adds the GPU HSL mixer stage.
    /// v9 adds three-way color grading. v10 replaces the master curve's 64³ cube with a sampled
    /// 1D Core Image kernel while preserving the piecewise-linear transfer function. v11 adds the
    /// GPU-backed Texture, Clarity, and Dehaze Effects stage. v12 adds the post-LUT vignette stage.
    static let cacheVersion = 12

    /// Build the graph for `document` over `source`.
    ///
    /// - Parameters:
    ///   - source: how to reproduce the source. A RAW is re-developed here, from the bytes, because
    ///     `CIRAWFilter` must be configured before it yields an image (§4.2).
    ///   - document: the look.
    ///   - lut: the LUT `document.lut.lutID` resolves to, or `nil`.
    ///   - scale: preview or full. Applied **early** — see `developedSource`.
    ///   - space: the LUT interpolation space. Output *encoding* is the engine's half of the seam;
    ///     both read one `WorkingSpace` so they cannot drift (§4.4).
    ///   - lutCache: reusable cube filters. `nil` builds one per call, which is correct but wasteful.
    ///
    /// - Returns: the graph, or `nil` if the source could not be decoded.
    ///
    /// **An unresolved LUT renders without the LUT rather than failing.** If `document.lut.lutID` is
    /// set but `lut` is `nil` — the file was deleted, the library has not finished scanning — this
    /// returns the ungraded image. Resolution is the caller's job and the caller is the layer that can
    /// report it; blanking the preview on every render would turn a missing file into a broken app,
    /// and reporting it per render would mean reporting it sixty times a second. Validate at load and
    /// report there (§7).
    static func buildImage(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace = .current,
        lutCache: LUTFilterCache? = nil
    ) -> CIImage? {
        guard let developed = developedSource(source, rawDevelop: document.rawDevelop, scale: scale) else {
            return nil
        }
        return buildImage(
            developed: developed, document: document, lut: lut, space: space, lutCache: lutCache,
            includePostRenderWhiteBalance: source.kind == .standard
        )
    }

    /// The graph from an **already-developed** source onwards — adjustments, LUT, then post-crop
    /// composition effects.
    ///
    /// Split out so a caller that already holds the developed image can skip the source stage.
    /// `RenderEngine` does exactly that, and it is not a micro-optimization: Core Image caches decoded
    /// intermediates **per `CIImage` instance**, so rebuilding the source image on every render throws
    /// that cache away and re-decodes the file. Measured on a 6000×4000 source, rebuilding it per
    /// render cost 156 ms against 0.6 ms for reusing one — a 272× regression on every intensity tick.
    ///
    /// This stays pure; the memo lives on the actor, where mutable state belongs.
    static func buildImage(
        developed: CIImage,
        document: EditDocument,
        lut: CubeLUT?,
        space: WorkingSpace = .current,
        lutCache: LUTFilterCache? = nil,
        toneCurveCache: ToneCurveFilterCache? = nil,
        includePostRenderWhiteBalance: Bool = true
    ) -> CIImage {
        let lightAdjusted = applyLight(document.light, to: developed, cache: toneCurveCache)
        let colorAdjusted = applyColor(document.color, to: lightAdjusted)
        // Detail/atmosphere effects are pre-LUT. Vignette is deliberately held until after the LUT
        // because it is a final composition effect and its mask must describe the post-crop frame.
        let effectsAdjusted = applyPreLUTEffects(document.effects, to: colorAdjusted)
        let adjustmentNodes = includePostRenderWhiteBalance
            ? document.adjustments
            : document.adjustments.filter { $0.slot != .temperatureTint }
        let adjusted = applyAdjustments(adjustmentNodes, to: effectsAdjusted)
        let lutAdjusted = applyLUT(document.lut, lut: lut, to: adjusted, space: space, cache: lutCache)
        return applyVignette(document.effects.vignette, to: lutAdjusted)
    }

    // MARK: - Source

    /// Decode the source at the requested scale.
    ///
    /// **Downscaling happens here, before anything else touches the pixels.** For RAW that means
    /// `CIRAWFilter.scaleFactor`, set before `outputImage`, so the decoder itself demosaics small; for
    /// a standard image it is a Lanczos step immediately after load. Either way the adjustment and LUT
    /// stages then operate on a preview-sized image rather than a 60-megapixel one.
    ///
    /// That is the whole reason every `AdjustmentNode` must use normalized units (§5): the graph a
    /// preview runs is the graph an export runs, at a different number of pixels.
    ///
    /// The scale is computed from the **decoder's** idea of the source size — `CIRAWFilter.nativeSize`
    /// or the decoded extent — not from `ImageSource.nativeExtent`. Both should agree, but only one of
    /// them is authoritative, and a caller that measured wrong should not be able to produce a
    /// mis-scaled render.
    static func developedSource(
        _ source: ImageSource,
        rawDevelop: RAWDevelopSettings,
        scale: RenderScale
    ) -> CIImage? {
        switch source.kind {
        case .raw:
            guard let filter = rawFilter(for: source.backing) else { return nil }
            rawDevelop.apply(to: filter)

            let factor = scale.factor(for: filter.nativeSize)
            if factor < 1 {
                filter.scaleFactor = Float(factor)
            }
            return filter.outputImage

        case .standard:
            guard let image = standardImage(for: source.backing) else { return nil }
            let factor = scale.factor(for: image.extent.size)
            guard factor < 1 else { return image }
            return lanczosScaled(image, by: factor)
        }
    }

    /// Internal rather than private since Step 10a: `RenderEngine.rawCapabilities` builds a filter
    /// purely to read its `is*Supported` flags, and duplicating the two-case construction would be
    /// two places for the `identifierHint` decision to drift.
    static func rawFilter(for backing: ImageSource.Backing) -> CIRAWFilter? {
        switch backing {
        case .url(let url):
            return CIRAWFilter(imageURL: url)
        case .data(let data):
            // No filename to hint with — the decoder identifies the format from the bytes, which is
            // the same thing `ImageSource.kind(forData:)` already did to classify it as RAW.
            return CIRAWFilter(imageData: data, identifierHint: nil)
        }
    }

    private static func standardImage(for backing: ImageSource.Backing) -> CIImage? {
        // `orientedLoadOptions` is shared with `ImageDecoder` on purpose: a portrait JPEG has to
        // come out of this pipeline the same way up as it comes out of the eager decode the view
        // model does at open, and `CIImage` ignores the EXIF tag unless asked.
        switch backing {
        case .url(let url):
            return CIImage(contentsOf: url, options: ImageDecoder.orientedLoadOptions)
        case .data(let data):
            return CIImage(data: data, options: ImageDecoder.orientedLoadOptions)
        }
    }

    private static func lanczosScaled(_ image: CIImage, by factor: CGFloat) -> CIImage {
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = image
        lanczos.scale = Float(factor)
        lanczos.aspectRatio = 1
        return lanczos.outputImage ?? image
    }

    // MARK: - Adjustments

    /// Apply the photographer-facing Light model before the inherited adjustment array.
    ///
    /// Exposure remains a native EV operation. The other Light controls share one five-point tone
    /// curve so their weights are tonal rather than spatial: contrast changes separation around the
    /// middle, highlights have most of their throw in the upper quarter, and shadows have the
    /// inverse shape. `CIToneCurve` is a Core Image node, so this stays in the same GPU-backed graph
    /// as the rest of the pipeline and does not require a CPU per-pixel pass.
    ///
    /// The editable master RGB curve is sampled into a small 1D texture and evaluated by one Core
    /// Image kernel. All three channels use the same transfer function; channel-specific curves can
    /// be added to the model without changing this stage's shape. The engine owns the reusable
    /// kernel/texture resource, while this overload remains stateless for callers and tests.
    ///
    /// Whites and Blacks are separate endpoint stages after the shared tonal curve. Keeping them
    /// separate gives each control an independent high- or low-end rolloff rather than making them
    /// aliases for Contrast.
    static func applyLight(
        _ light: LightAdjustments,
        to image: CIImage,
        cache: ToneCurveFilterCache? = nil
    ) -> CIImage {
        var result = image

        if light.exposure != 0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = result
            filter.ev = Float(light.exposure)
            result = filter.outputImage ?? result
        }

        if light.contrast != 0 || light.highlights != 0 || light.shadows != 0 {
            let curve = CIFilter.toneCurve()
            curve.inputImage = result

            let contrast = CGFloat(light.contrast / 100)
            let highlights = CGFloat(light.highlights / 100)
            let shadows = CGFloat(light.shadows / 100)

            // Fixed endpoints keep a moderate contrast move from clipping usable blacks and whites.
            // The slider deltas are deliberately bounded well inside the endpoint interval, and the
            // interior weights taper toward the opposite tonal region.
            //
            // Opposing controls (e.g. negative Contrast with positive Shadows and negative Highlights)
            // can otherwise push an interior point below its lower neighbor, which makes CIToneCurve's
            // spline invert tones locally instead of just changing separation. Clamp each interior point
            // to be no lower than the previous one so the curve stays monotonic for every slider
            // combination.
            var output1 = clampedToneValue(0.25 - 0.12 * contrast + 0.15 * shadows)
            var output2 = clampedToneValue(0.5 + 0.025 * (highlights + shadows))
            var output3 = clampedToneValue(0.75 + 0.12 * contrast + 0.15 * highlights)
            output1 = max(output1, 0)
            output2 = max(output2, output1)
            output3 = max(output3, output2)

            curve.point0 = toneCurvePoint(input: 0, output: 0)
            curve.point1 = toneCurvePoint(input: 0.25, output: output1)
            curve.point2 = toneCurvePoint(input: 0.5, output: output2)
            curve.point3 = toneCurvePoint(input: 0.75, output: output3)
            curve.point4 = toneCurvePoint(input: 1, output: 1)

            result = curve.outputImage ?? result
        }

        if !light.toneCurve.isIdentity {
            result = applyToneCurve(light.toneCurve, to: result, cache: cache)
        }

        // Endpoint controls intentionally run in a stable order after the shared tonal curve:
        // high-end Whites first, low-end Blacks second. Each is a distinct GPU stage, so changing
        // one endpoint does not silently change the other control's curve.
        if light.whites != 0 {
            result = applyWhitePoint(light.whites, to: result)
        }
        if light.blacks != 0 {
            result = applyBlackPoint(light.blacks, to: result)
        }
        return result
    }

    // MARK: - Color

    /// Apply global colour controls after Light and before the legacy ordered adjustment array.
    ///
    /// Core Image owns the per-pixel work for both controls. Vibrance runs first so it can protect
    /// already-colourful pixels before the final global saturation multiplier is applied. At the
    /// photographer-facing endpoints, saturation -100 maps to `inputSaturation = 0` (near
    /// monochrome after the filter's luminance weighting), 0 maps to the exact filter identity, and
    /// +100 maps to 2×. Vibrance -100...+100 maps linearly to `inputAmount` -1...+1.
    ///
    /// Core Image preserves input alpha and colour-space metadata; output encoding is still
    /// performed by the caller with the request's `WorkingSpace`, so preview and export use the
    /// same gamut boundary. Values are finite and clamped by `ColorAdjustments` before reaching
    /// this stage. The fixed order is global vibrance, global saturation, HSL mixer, and three-way
    /// grading; ordered effects and the LUT remain downstream in `buildImage`.
    static func applyColor(_ color: ColorAdjustments, to image: CIImage) -> CIImage {
        guard !color.isIdentity else { return image }
        var result = image

        if color.vibrance != 0 {
            let filter = CIFilter.vibrance()
            filter.inputImage = result
            filter.amount = Float(color.normalizedVibrance)
            result = filter.outputImage ?? result
        }

        if color.saturation != 0 {
            let filter = CIFilter.colorControls()
            filter.inputImage = result
            filter.brightness = 0
            filter.contrast = 1
            filter.saturation = Float(color.normalizedSaturation)
            result = filter.outputImage ?? result
        }

        if !color.mixer.isIdentity {
            result = applyColorMixer(color.mixer, to: result)
        }

        if !color.grading.isIdentity {
            result = applyColorGrading(color.grading, to: result)
        }

        return result
    }

    // MARK: - HSL mixer

    // MARK: - Effects

    /// Apply the global photographic Effects controls as one lazy Core Image graph.
    ///
    /// Texture and Clarity use different spatial scales: Texture is a small-radius luminance
    /// detail operation, while Clarity uses a broader local operation and a smooth midtone mask.
    /// Dehaze is intentionally not another sharpen slider: it combines a broader local operation
    /// with contrast, saturation, and a restrained S-curve so positive values reduce the veiled
    /// appearance of low-contrast colour, while negative values produce the inverse haze-like look.
    ///
    /// All radii are fractions of the current image's shortest side. Since source downscaling is
    /// performed before this stage, preview and export use the same photographic radius relative to
    /// the image rather than accidentally using the same number of pixels.
    static func applyEffects(_ effects: EffectsAdjustments, to image: CIImage) -> CIImage {
        let preLUT = applyPreLUTEffects(effects, to: image)
        return applyVignette(effects.vignette, to: preLUT)
    }

    /// Apply the detail/atmosphere controls that belong before the LUT. Kept separate from the
    /// convenience above so the full pipeline can place vignette after LUT exactly once.
    private static func applyPreLUTEffects(_ effects: EffectsAdjustments, to image: CIImage) -> CIImage {
        guard effects.texture != 0 || effects.clarity != 0 || effects.dehaze != 0 else { return image }
        var result = image

        if effects.texture != 0 {
            result = applyTexture(effects.texture, to: result)
        }
        if effects.clarity != 0 {
            result = applyClarity(effects.clarity, to: result)
        }
        if effects.dehaze != 0 {
            result = applyDehaze(effects.dehaze, to: result)
        }
        return result
    }

    /// Apply a vignette over the current (post-crop) image extent. The mask uses normalized
    /// coordinates in both axes, so a 4:3 image gets an ellipse that reaches its left/right and
    /// top/bottom edges at the same normalized distance rather than a circle stretched by pixels.
    /// Every operation is clipped back to that extent; vignette never changes output dimensions.
    static func applyVignette(_ vignette: VignetteAdjustments, to image: CIImage) -> CIImage {
        guard !vignette.isIdentity,
              let kernel = vignetteKernel,
              image.extent.width.isFinite,
              image.extent.height.isFinite,
              image.extent.width > 0,
              image.extent.height > 0
        else { return image }

        let extent = image.extent
        let geometry = CIVector(
            x: extent.midX,
            y: extent.midY,
            z: extent.width / 2,
            w: extent.height / 2
        )
        let shape = CIVector(
            x: vignette.midpoint / 100,
            y: vignette.roundness / 100,
            z: vignette.feather / 100,
            w: vignette.amount / 100
        )
        let highlight = CIVector(x: vignette.highlights / 100, y: 0, z: 0, w: 0)
        return kernel.apply(
            extent: extent,
            roiCallback: { _, rect in rect },
            arguments: [image, geometry, shape, highlight]
        )?.cropped(to: extent) ?? image
    }

    /// Texture is a small-radius luminance detail operation. Negative Texture uses the same
    /// narrow neighbourhood as a softening operation, so its inverse does not become a global blur.
    private static func applyTexture(_ value: Double, to image: CIImage) -> CIImage {
        let amount = CGFloat(abs(value) / EffectsAdjustments.textureRange.upperBound)
        let radius = normalizedRadius(0.004, for: image)
        let effect: CIImage
        if value > 0 {
            effect = image.applyingFilter("CISharpenLuminance", parameters: [
                "inputSharpness": 0.85 * amount,
                "inputRadius": radius,
            ])
        } else {
            effect = croppedBlur(image, radius: radius * 0.7)
        }
        return blend(effect: effect, over: image, amount: amount, mask: nil, extent: image.extent)
    }

    /// Clarity is broader local contrast, restricted by a smooth midtone weighting. The mask keeps
    /// skies and deep shadows from receiving the same edge emphasis as photographic midtones.
    private static func applyClarity(_ value: Double, to image: CIImage) -> CIImage {
        let amount = CGFloat(abs(value) / EffectsAdjustments.clarityRange.upperBound)
        let radius = normalizedRadius(0.028, for: image)
        let effect = value > 0
            ? image.applyingFilter("CISharpenLuminance", parameters: [
                "inputRadius": radius,
                "inputSharpness": 0.95 * amount,
            ])
            : croppedBlur(image, radius: radius * 0.7)
        let mask = midtoneMask(for: image, amount: amount)
        return blend(effect: effect, over: image, amount: 1, mask: mask, extent: image.extent)
    }

    /// Dehaze combines broad local contrast with global tone and colour separation. The global
    /// terms are intentionally restrained: at moderate settings the operation remains reversible
    /// and avoids making clipped highlights or artificial halos the primary visual effect.
    private static func applyDehaze(_ value: Double, to image: CIImage) -> CIImage {
        let amount = CGFloat(abs(value) / EffectsAdjustments.dehazeRange.upperBound)
        let radius = normalizedRadius(0.026, for: image)
        let local: CIImage
        if value > 0 {
            local = image.applyingFilter("CIUnsharpMask", parameters: [
                "inputRadius": radius,
                "inputIntensity": 0.65 * amount,
            ])
        } else {
            local = croppedBlur(image, radius: radius * 0.8)
        }

        var result = blend(effect: local, over: image, amount: amount, mask: nil, extent: image.extent)
        let controls = CIFilter.colorControls()
        controls.inputImage = result
        controls.brightness = 0
        controls.contrast = Float(1 + (value > 0 ? 0.28 : -0.22) * amount)
        controls.saturation = Float(1 + (value > 0 ? 0.16 : -0.14) * amount)
        result = controls.outputImage ?? result
        return applyDehazeTone(value, amount: amount, to: result)
    }

    /// A shallow S-curve supplies the tonal part of Dehaze without reusing the Clarity midtone
    /// mask. It is kept as a dedicated GPU tone node so the three controls remain independently
    /// observable on both frequency patterns and smooth tonal regions.
    private static func applyDehazeTone(_ value: Double, amount: CGFloat, to image: CIImage) -> CIImage {
        let curve = CIFilter.toneCurve()
        curve.inputImage = image
        let direction: CGFloat = value > 0 ? 1 : -1
        curve.point0 = toneCurvePoint(input: 0, output: 0)
        curve.point1 = toneCurvePoint(input: 0.25, output: 0.25 - 0.035 * direction * amount)
        curve.point2 = toneCurvePoint(input: 0.5, output: 0.5)
        curve.point3 = toneCurvePoint(input: 0.75, output: 0.75 + 0.035 * direction * amount)
        curve.point4 = toneCurvePoint(input: 1, output: 1)
        return curve.outputImage ?? image
    }

    private static func normalizedRadius(_ fraction: CGFloat, for image: CIImage) -> CGFloat {
        let extent = image.extent
        let shortestSide = min(abs(extent.width), abs(extent.height))
        guard shortestSide.isFinite, shortestSide > 0 else { return 1 }
        return max(0.5, shortestSide * fraction)
    }

    private static func croppedBlur(_ image: CIImage, radius: CGFloat) -> CIImage {
        image.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": radius])
            .cropped(to: image.extent)
    }

    private static func blend(
        effect: CIImage,
        over image: CIImage,
        amount: CGFloat,
        mask: CIImage?,
        extent: CGRect
    ) -> CIImage {
        let maskImage = mask ?? CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: extent)
        return effectsBlendKernel?.apply(
            extent: extent,
            roiCallback: { _, rect in rect },
            arguments: [image, effect.cropped(to: extent), maskImage, amount]
        )?.cropped(to: extent) ?? image
    }

    private static func midtoneMask(for image: CIImage, amount: CGFloat) -> CIImage {
        midtoneMaskKernel?.apply(
            extent: image.extent,
            arguments: [image, CIVector(x: amount, y: 0, z: 0, w: 0)]
        ) ?? image
    }

    private static let midtoneMaskKernel = CIColorKernel(source: """
    kernel vec4 effectsMidtoneMask(__sample pixel, vec4 controls) {
        if (pixel.a <= 0.00001) { return vec4(0.0); }
        vec3 rgb = clamp(pixel.rgb / pixel.a, 0.0, 1.0);
        float luminance = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
        // A smooth bell centred on middle gray, zero at both endpoints.
        float weight = clamp(4.0 * luminance * (1.0 - luminance), 0.0, 1.0);
        float alpha = weight * clamp(controls.x, 0.0, 1.0);
        return vec4(0.0, 0.0, 0.0, alpha);
    }
    """)

    private static let effectsBlendKernel = CIKernel(source: """
    kernel vec4 effectsBlend(sampler original, sampler effect, sampler mask, float amount) {
        vec2 coordinate = samplerCoord(original);
        vec4 base = sample(original, coordinate);
        vec4 altered = sample(effect, coordinate);
        vec4 maskPixel = sample(mask, coordinate);
        float mixAmount = clamp(amount * maskPixel.a, 0.0, 1.0);
        return mix(base, altered, mixAmount);
    }
    """)

    private static let vignetteKernel = CIKernel(source: """
    kernel vec4 effectsVignette(
        sampler image,
        vec4 geometry,
        vec4 shape,
        vec4 highlightControls
    ) {
        vec2 coordinate = samplerCoord(image);
        vec4 pixel = sample(image, coordinate);
        if (pixel.a <= 0.00001) { return pixel; }

        // Normalize independently by half-width/half-height: crop aspect ratio is part of the
        // geometry, while the vignette values remain resolution independent.
        vec2 normalized = (coordinate - geometry.xy) / max(geometry.zw, vec2(0.00001));
        float roundness = clamp(shape.y, -1.0, 1.0);
        // p=4 is squarer and p=2 is circular. Positive Roundness therefore rounds the corners.
        float exponent = 3.0 - roundness;
        float radius = pow(pow(abs(normalized.x), exponent) +
                            pow(abs(normalized.y), exponent), 1.0 / exponent);

        float midpoint = clamp(shape.x, 0.0, 1.0);
        float feather = clamp(shape.z, 0.0, 1.0);
        float transition = max(0.015, 0.08 + feather * 0.42);
        float edge = smoothstep(max(0.0, midpoint - transition),
                                min(1.5, midpoint + transition), radius);

        vec3 straight = clamp(pixel.rgb / pixel.a, 0.0, 1.0);
        float luminance = dot(straight, vec3(0.2126, 0.7152, 0.0722));
        float highlightWeight = smoothstep(0.55, 1.0, luminance);
        float preservation = 1.0 - clamp(highlightControls.x, 0.0, 1.0) * highlightWeight;
        float signedAmount = clamp(shape.w, -1.0, 1.0);
        float multiplier = 1.0 - signedAmount * edge * preservation;
        return vec4(pixel.rgb * multiplier, pixel.a);
    }
    """)

    /// Apply the eight-channel mixer in one Core Image color kernel.
    ///
    /// Channel weights are raised cosine windows around the fixed Lightroom-style centers
    /// (R/O/Y/G/A/B/P/M). A 45° support radius gives adjacent channels a smooth overlap, while the
    /// circular distance makes the red window continuous across hue 0/1. The kernel computes all
    /// weights from the original pixel hue, then applies one combined HSL adjustment; there are no
    /// CPU per-pixel operations and no sequence of hard channel masks that could leave seams.
    ///
    /// Hue is limited to ±30° at the UI endpoints, while Saturation is a ±1 HSL delta and
    /// Luminance is a ±0.5 lightness delta. HSL is used only as the local mixer coordinate system;
    /// the surrounding image remains in the request's working color space and alpha is copied
    /// through unchanged.
    static func applyColorMixer(_ mixer: ColorMixerAdjustments, to image: CIImage) -> CIImage {
        guard !mixer.isIdentity,
              let kernel = hslMixerKernel
        else { return image }

        let parameters: [Any] = [
            mixerKernelVector(mixer.red), mixerKernelVector(mixer.orange),
            mixerKernelVector(mixer.yellow), mixerKernelVector(mixer.green),
            mixerKernelVector(mixer.aqua), mixerKernelVector(mixer.blue),
            mixerKernelVector(mixer.purple), mixerKernelVector(mixer.magenta),
        ]

        // `__sample` supplies the image argument first. The eight following vec4s are a compact
        // value payload, which keeps the kernel signature fixed and avoids allocating a filter per
        // channel or touching pixels on the CPU.
        return kernel.apply(extent: image.extent, arguments: [image] + parameters) ?? image
    }

    private static func mixerKernelVector(_ channel: ColorMixerChannel) -> CIVector {
        // 100 mixer hue units represent a useful photographic ±30° move.
        CIVector(
            x: channel.hue / 100 * (30.0 / 360.0),
            y: channel.saturation / 100,
            z: channel.luminance / 100,
            w: 0
        )
    }

    private static let hslMixerKernel: CIColorKernel? = CIColorKernel(source: hslMixerKernelSource)

    private static let hslMixerKernelSource = """
    float wrappedHue(float value) {
        return value - floor(value);
    }

    float circularDistance(float hue, float center) {
        float distance = abs(hue - center);
        return min(distance, 1.0 - distance);
    }

    float hueWeight(float hue, float center) {
        // Raised cosine: both the value and its first derivative reach zero at the edge.
        float radius = 0.125;
        float distance = circularDistance(hue, center);
        if (distance >= radius) { return 0.0; }
        return 0.5 + 0.5 * cos(3.141592653589793 * distance / radius);
    }

    float hueToRGB(float p, float q, float t) {
        float wrapped = wrappedHue(t);
        if (wrapped < 1.0 / 6.0) { return p + (q - p) * 6.0 * wrapped; }
        if (wrapped < 1.0 / 2.0) { return q; }
        if (wrapped < 2.0 / 3.0) { return p + (q - p) * (2.0 / 3.0 - wrapped) * 6.0; }
        return p;
    }

    vec3 hslToRGB(float hue, float saturation, float luminance) {
        if (saturation <= 0.00001) {
            return vec3(luminance, luminance, luminance);
        }
        float q = luminance < 0.5
            ? luminance * (1.0 + saturation)
            : luminance + saturation - luminance * saturation;
        float p = 2.0 * luminance - q;
        return vec3(
            hueToRGB(p, q, hue + 1.0 / 3.0),
            hueToRGB(p, q, hue),
            hueToRGB(p, q, hue - 1.0 / 3.0)
        );
    }

    kernel vec4 hslMixer(
        __sample pixel,
        vec4 red,
        vec4 orange,
        vec4 yellow,
        vec4 green,
        vec4 aqua,
        vec4 blue,
        vec4 purple,
        vec4 magenta
    ) {
        // Core Image kernel samples are premultiplied. HSL must see the unpremultiplied colour,
        // then the result is premultiplied again so transparent pixels retain both alpha and the
        // compositing contract of the input image.
        if (pixel.a <= 0.00001) { return pixel; }
        vec3 rgb = clamp(pixel.rgb / pixel.a, 0.0, 1.0);
        float maximum = max(max(rgb.r, rgb.g), rgb.b);
        float minimum = min(min(rgb.r, rgb.g), rgb.b);
        float delta = maximum - minimum;

        // Neutrals have no hue neighborhood. Returning the original sample also avoids assigning
        // gray pixels an arbitrary red hue when only one channel is adjusted.
        if (delta <= 0.00001) { return pixel; }

        float luminance = 0.5 * (maximum + minimum);
        float saturation = delta / (1.0 - abs(2.0 * luminance - 1.0));
        float hue;
        if (maximum == rgb.r) {
            hue = (rgb.g - rgb.b) / delta;
            if (hue < 0.0) { hue += 6.0; }
            hue /= 6.0;
        } else if (maximum == rgb.g) {
            hue = ((rgb.b - rgb.r) / delta + 2.0) / 6.0;
        } else {
            hue = ((rgb.r - rgb.g) / delta + 4.0) / 6.0;
        }
        hue = wrappedHue(hue);

        float redWeight = hueWeight(hue, 0.0);
        float orangeWeight = hueWeight(hue, 1.0 / 12.0);
        float yellowWeight = hueWeight(hue, 1.0 / 6.0);
        float greenWeight = hueWeight(hue, 1.0 / 3.0);
        float aquaWeight = hueWeight(hue, 1.0 / 2.0);
        float blueWeight = hueWeight(hue, 2.0 / 3.0);
        float purpleWeight = hueWeight(hue, 3.0 / 4.0);
        float magentaWeight = hueWeight(hue, 5.0 / 6.0);

        float hueDelta = redWeight * red.x + orangeWeight * orange.x
            + yellowWeight * yellow.x + greenWeight * green.x
            + aquaWeight * aqua.x + blueWeight * blue.x
            + purpleWeight * purple.x + magentaWeight * magenta.x;
        float saturationDelta = redWeight * red.y + orangeWeight * orange.y
            + yellowWeight * yellow.y + greenWeight * green.y
            + aquaWeight * aqua.y + blueWeight * blue.y
            + purpleWeight * purple.y + magentaWeight * magenta.y;
        float luminanceDelta = redWeight * red.z + orangeWeight * orange.z
            + yellowWeight * yellow.z + greenWeight * green.z
            + aquaWeight * aqua.z + blueWeight * blue.z
            + purpleWeight * purple.z + magentaWeight * magenta.z;

        return vec4(
            hslToRGB(
                wrappedHue(hue + hueDelta),
                clamp(saturation + saturationDelta, 0.0, 1.0),
                clamp(luminance + 0.5 * luminanceDelta, 0.0, 1.0)
            ) * pixel.a,
            pixel.a
        );
    }
    """

    // MARK: - Three-way color grading

    /// Apply shadows, midtones, and highlights in one GPU color kernel.
    ///
    /// The tonal masks are smooth partitions of luminance. At zero blending their boundaries
    /// meet; increasing blending moves the boundaries toward one another, creating a predictable
    /// overlap that is normalized before the wheel colors are combined. Balance shifts the sampled
    /// luminance before those masks are evaluated, so it moves a pixel between regions without
    /// changing the overlap width. The kernel colorizes the source luminance toward each wheel's
    /// hue and mixes by saturation, which also means neutral grayscale pixels can be graded.
    static func applyColorGrading(_ grading: ColorGradingAdjustments, to image: CIImage) -> CIImage {
        guard !grading.isIdentity,
              let kernel = colorGradingKernel
        else { return image }

        let parameters: [Any] = [
            gradingKernelVector(grading.shadows),
            gradingKernelVector(grading.midtones),
            gradingKernelVector(grading.highlights),
            CIVector(
                x: grading.blending / 100,
                y: grading.balance / 100,
                z: 0,
                w: 0
            ),
        ]
        return kernel.apply(extent: image.extent, arguments: [image] + parameters) ?? image
    }

    private static func gradingKernelVector(_ wheel: ColorGradingWheel) -> CIVector {
        CIVector(x: wheel.hue / 360, y: wheel.saturation / 100, z: 0, w: 0)
    }

    private static let colorGradingKernel: CIColorKernel? =
        CIColorKernel(source: colorGradingKernelSource)

    private static let colorGradingKernelSource = """
    float wrappedGradingHue(float value) {
        return value - floor(value);
    }

    float gradingHueToRGB(float p, float q, float t) {
        float wrapped = wrappedGradingHue(t);
        if (wrapped < 1.0 / 6.0) { return p + (q - p) * 6.0 * wrapped; }
        if (wrapped < 1.0 / 2.0) { return q; }
        if (wrapped < 2.0 / 3.0) { return p + (q - p) * (2.0 / 3.0 - wrapped) * 6.0; }
        return p;
    }

    vec3 gradingColor(float hue, float luminance) {
        // Full-saturation HSL at the source luminance is the wheel's target color. The caller
        // controls how far toward it to move with the wheel saturation.
        float q = luminance < 0.5
            ? luminance * 2.0
            : luminance + 1.0 - luminance;
        float p = 2.0 * luminance - q;
        return vec3(
            gradingHueToRGB(p, q, hue + 1.0 / 3.0),
            gradingHueToRGB(p, q, hue),
            gradingHueToRGB(p, q, hue - 1.0 / 3.0)
        );
    }

    float gradingSmoothStep(float edge0, float edge1, float value) {
        float denominator = max(edge1 - edge0, 0.00001);
        float t = clamp((value - edge0) / denominator, 0.0, 1.0);
        return t * t * (3.0 - 2.0 * t);
    }

    kernel vec4 colorGrading(
        __sample pixel,
        vec4 shadows,
        vec4 midtones,
        vec4 highlights,
        vec4 controls
    ) {
        if (pixel.a <= 0.00001) { return pixel; }
        vec3 rgb = clamp(pixel.rgb / pixel.a, 0.0, 1.0);
        float luminance = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
        float shiftedLuminance = clamp(luminance + controls.y * 0.25, 0.0, 1.0);
        float blending = clamp(controls.x, 0.0, 1.0);

        // At blending 0 these transitions meet. At blending 1 they overlap by 0.16 of the
        // normalized luminance range. The normalized weights always sum to one.
        float shadowEdge = 0.42 + 0.16 * blending;
        float highlightEdge = 0.58 - 0.16 * blending;
        float shadowWeight = 1.0 - gradingSmoothStep(0.0, shadowEdge, shiftedLuminance);
        float highlightWeight = gradingSmoothStep(highlightEdge, 1.0, shiftedLuminance);
        float midtoneWeight = gradingSmoothStep(0.0, shadowEdge, shiftedLuminance)
            * (1.0 - gradingSmoothStep(highlightEdge, 1.0, shiftedLuminance));
        float weightTotal = max(shadowWeight + midtoneWeight + highlightWeight, 0.00001);
        shadowWeight /= weightTotal;
        midtoneWeight /= weightTotal;
        highlightWeight /= weightTotal;

        float shadowAmount = shadowWeight * clamp(shadows.y, 0.0, 1.0);
        float midtoneAmount = midtoneWeight * clamp(midtones.y, 0.0, 1.0);
        float highlightAmount = highlightWeight * clamp(highlights.y, 0.0, 1.0);
        float amountTotal = shadowAmount + midtoneAmount + highlightAmount;
        if (amountTotal <= 0.00001) { return pixel; }

        vec3 tint = (
            shadowAmount * gradingColor(shadows.x, luminance)
            + midtoneAmount * gradingColor(midtones.x, luminance)
            + highlightAmount * gradingColor(highlights.x, luminance)
        ) / amountTotal;
        vec3 graded = mix(rgb, tint, clamp(amountTotal, 0.0, 1.0));
        return vec4(clamp(graded, 0.0, 1.0) * pixel.a, pixel.a);
    }
    """

    private static func applyToneCurve(
        _ curve: LightToneCurve,
        to image: CIImage,
        cache: ToneCurveFilterCache?
    ) -> CIImage {
        if let cache { return cache.apply(curve, to: image) }
        return ToneCurveFilterCache().apply(curve, to: image)
    }

    /// Move the white point with a smooth high-end rolloff. The first three control points stay on
    /// the diagonal, while the upper quarter and endpoint carry the edit. Values above 1 are
    /// intentional for positive Whites: Core Image clips them at a raster output while retaining
    /// highlight headroom in the lazy graph.
    private static func applyWhitePoint(_ value: Double, to image: CIImage) -> CIImage {
        let amount = CGFloat(value / LightAdjustments.whitesRange.upperBound)
        let curve = CIFilter.toneCurve()
        curve.inputImage = image
        curve.point0 = toneCurvePoint(input: 0, output: 0)
        curve.point1 = toneCurvePoint(input: 0.25, output: 0.25)
        curve.point2 = toneCurvePoint(input: 0.5, output: 0.5)
        curve.point3 = toneCurvePoint(input: 0.75, output: 0.75 + 0.10 * amount)
        curve.point4 = toneCurvePoint(input: 1, output: 1 + 0.20 * amount)
        return curve.outputImage ?? image
    }

    /// Move the black point with a smooth low-end rolloff. The endpoint receives the strongest
    /// movement and the quarter-tone point receives a smaller share, leaving the upper half alone.
    private static func applyBlackPoint(_ value: Double, to image: CIImage) -> CIImage {
        let amount = CGFloat(value / LightAdjustments.blacksRange.upperBound)
        let curve = CIFilter.toneCurve()
        curve.inputImage = image
        curve.point0 = endpointToneCurvePoint(input: 0, output: 0.16 * amount)
        curve.point1 = endpointToneCurvePoint(input: 0.25, output: 0.25 + 0.10 * amount)
        curve.point2 = endpointToneCurvePoint(input: 0.5, output: 0.5)
        curve.point3 = endpointToneCurvePoint(input: 0.75, output: 0.75)
        curve.point4 = endpointToneCurvePoint(input: 1, output: 1)
        return curve.outputImage ?? image
    }

    private static func clampedToneValue(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    /// `CIToneCurve` interpolates in a gamma-2/perceptual domain. Specify the curve in linear-light
    /// coordinates so the photographer-facing weights above retain their intended meaning for a
    /// linear ramp as well as for normal encoded photographs.
    private static func toneCurvePoint(input: CGFloat, output: CGFloat) -> CGPoint {
        CGPoint(x: sqrt(input), y: sqrt(output))
    }

    /// Endpoint controls can intentionally request a negative black point. Core Image clips the
    /// resulting tone at zero, but the perceptual-coordinate conversion itself must never receive a
    /// negative value (sqrt would create a NaN before Core Image can do that clipping).
    private static func endpointToneCurvePoint(input: CGFloat, output: CGFloat) -> CGPoint {
        CGPoint(x: sqrt(max(input, 0)), y: sqrt(max(output, 0)))
    }

    /// Fold the ordered nodes over the image.
    ///
    /// Nodes at their identity values are skipped. That is an optimization, not a behaviour change:
    /// all five filters are bit-exact pass-throughs at the values `AdjustmentNode.isIdentity` names —
    /// measured, and pinned by `testSkippingIdentityNodesChangesNothing`.
    static func applyAdjustments(_ nodes: [AdjustmentNode], to image: CIImage) -> CIImage {
        nodes.reduce(image) { partial, node in
            node.isIdentity ? partial : (filter(for: node, input: partial) ?? partial)
        }
    }

    /// The node → `CIFilter` mapping. Built through `CIFilterBuiltins`, so the parameter names are
    /// checked by the compiler rather than spelled as strings.
    private static func filter(for node: AdjustmentNode, input: CIImage) -> CIImage? {
        switch node {
        case .exposure(let ev):
            let f = CIFilter.exposureAdjust()
            f.inputImage = input
            f.ev = Float(ev)
            return f.outputImage

        case .colorControls(let brightness, let contrast, let saturation):
            let f = CIFilter.colorControls()
            f.inputImage = input
            f.brightness = Float(brightness)
            f.contrast = Float(contrast)
            f.saturation = Float(saturation)
            return f.outputImage

        case .highlightShadow(let highlights, let shadows):
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = input
            f.highlightAmount = Float(highlights)
            f.shadowAmount = Float(shadows)
            return f.outputImage

        case .temperatureTint(let temp, let tint):
            let f = CIFilter.temperatureAndTint()
            f.inputImage = input
            // Source neutral is pinned at D65; only the target moves. This is what makes identity
            // land at (6500, 0) — and also what pins the node's own Kelvin direction backwards:
            // raising Kelvin cools the image, held by testRaisingKelvinCoolsTheImage. §8.7 is
            // closed: the Adjust panel's slider is reflected about D65 in
            // AdjustmentControl.sliderMapped(_:), so both Kelvin sliders in the inspector warm
            // rightward without touching this line. Changing *this* line instead changes stored
            // pixel behaviour for every document — a different and much larger act than flipping a
            // slider's display mapping.
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: temp, y: tint)
            return f.outputImage

        case .vibrance(let amount):
            let f = CIFilter.vibrance()
            f.inputImage = input
            f.amount = Float(amount)
            return f.outputImage
        }
    }

    // MARK: - LUT

    private static func applyLUT(
        _ settings: LUTSettings,
        lut: CubeLUT?,
        to image: CIImage,
        space: WorkingSpace,
        cache: LUTFilterCache?
    ) -> CIImage {
        guard !settings.isIdentity, let lut else { return image }

        let cubeFilter = cache?.filter(for: lut, space: space) ?? lut.makeFilter(space: space)
        return lut.apply(to: image, intensity: settings.intensity, using: cubeFilter) ?? image
    }
}
