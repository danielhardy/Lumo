import CoreImage

/// The stage-composition seam between the request façade and the pure Core Image pipeline.
///
/// `RenderPipeline` owns the individual transformations. This façade owns only their final
/// composition contract, so `RenderEngine` does not need to know which stages are below the LUT or
/// how deterministic grain is seeded. The cache object remains actor-confined by the caller.
enum RenderStageFacade {
    /// Apply the post-prefix stages in the product's canonical order: LUT, crop, post-crop
    /// vignette, and deterministic grain.
    static func buildFinalStages(
        preLUT image: CIImage,
        document: EditDocument,
        lut: CubeLUT?,
        space: WorkingSpace,
        lutCache: LUTFilterCache,
        grainSeed: UInt32
    ) -> CIImage {
        RenderPipeline.buildImage(
            preLUT: image,
            document: document,
            lut: lut,
            space: space,
            lutCache: lutCache,
            grainSeed: grainSeed
        )
    }
}
