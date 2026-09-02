import SwiftUI

/// Main image preview area. Supports side-by-side (original vs Look)
/// and single-image mode. Hold Space to flash original in single mode.
struct PreviewView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var dragTranslation: CGSize = .zero
    @State private var magnification: CGFloat = 1
    @State private var isDraggingCanvas = false
    @State private var isMagnifyingCanvas = false

    /// The shell around the Metal image surface follows the window appearance. The Metal
    /// surface's letterbox remains intentionally dark because it is part of image presentation,
    /// not window chrome; see `PreviewSurfaceView`.
    private var bgColor: Color { LumoTheme.windowBackground }

    var body: some View {
        ZStack {
            bgColor

            if viewModel.sourceImage != nil {
                if viewModel.isCropToolActive {
                    singleView
                } else if viewModel.isSideBySideVisible {
                    sideBySideView
                } else {
                    singleView
                }
            } else if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(.circular)
            } else {
                emptyState
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Side-by-side

    private var sideBySideView: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                // Original
                panelView(
                    surface: viewModel.originalPreviewSurface,
                    label: "Original",
                    labelSide: .leading,
                    width: geo.size.width / 2
                )

                // Divider
                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 1)

                // Look applied
                panelView(
                    surface: viewModel.previewSurface,
                    label: viewModel.selectedLook?.name ?? "Adjusted",
                    labelSide: .trailing,
                    width: geo.size.width / 2
                )
            }
        }
        .padding(8)
    }

    private func panelView(surface: PreviewSurface, label: String, labelSide: HorizontalAlignment, width: CGFloat) -> some View {
        ZStack(alignment: labelSide == .leading ? .topLeading : .topTrailing) {
            bgColor

            if surface.image != nil { canvasSurface(surface) }

            ComparisonBadge(text: label)
                .padding(12)
        }
        .frame(width: width)
        .clipped()
    }

    // MARK: - Single image

    private var singleView: some View {
        GeometryReader { geometry in
            ZStack {
                if viewModel.previewSurface.image != nil {
                    canvasSurface(viewModel.previewSurface)
                        .padding(8)
                }

                if viewModel.isCropToolActive, viewModel.sourceSize != .zero {
                    CropOverlayView(
                        normalizedRect: viewModel.cropDraft ?? CropAdjustments.unitRect,
                        imageSize: viewModel.sourceSize,
                        onChange: viewModel.updateCropDraft,
                        onApply: viewModel.commitCrop,
                        onReset: viewModel.resetCrop,
                        onCancel: viewModel.cancelCrop
                    )
                    .padding(8)
                }

                if viewModel.previewSurface.image != nil {
                    // Comparison badge
                    if viewModel.isShowingOriginal && viewModel.isComparisonAvailable {
                        VStack {
                            HStack {
                                ComparisonBadge(text: "Original")
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(20)
                    }

                    // Look name badge
                    if !viewModel.isShowingOriginal, let look = viewModel.selectedLook {
                        VStack {
                            HStack {
                                Spacer()
                                ComparisonBadge(text: look.name)
                            }
                            Spacer()
                        }
                        .padding(20)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    /// A full-panel surface with presentation-only mouse and trackpad navigation. The same
    /// navigation value is passed to both comparison panels, so before/after remains registered.
    private func canvasSurface(_ surface: PreviewSurface) -> some View {
        GeometryReader { geometry in
            PreviewSurfaceView(
                surface: surface,
                navigation: viewModel.canvasNavigation,
                onScrollZoom: { factor in viewModel.zoomCanvas(by: factor) },
                onDrawableSizeChange: { size in viewModel.updatePreviewBackingSize(size) }
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(!viewModel.isCropToolActive)
                .contentShape(Rectangle())
                .gesture(dragGesture(viewportSize: geometry.size))
                .simultaneousGesture(magnificationGesture(viewportSize: geometry.size))
        }
    }

    private func dragGesture(viewportSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !isDraggingCanvas {
                    isDraggingCanvas = true
                    dragTranslation = .zero
                }
                let delta = CGSize(
                    width: value.translation.width - dragTranslation.width,
                    height: value.translation.height - dragTranslation.height
                )
                dragTranslation = value.translation
                viewModel.panCanvas(by: delta, viewportSize: viewportSize)
            }
            .onEnded { _ in
                guard isDraggingCanvas else { return }
                isDraggingCanvas = false
                dragTranslation = .zero
            }
    }

    private func magnificationGesture(viewportSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if !isMagnifyingCanvas {
                    isMagnifyingCanvas = true
                    magnification = 1
                    viewModel.beginCanvasInteraction()
                }
                guard value.isFinite, value > 0 else { return }
                viewModel.zoomCanvas(by: value / magnification)
                magnification = value
            }
            .onEnded { _ in
                guard isMagnifyingCanvas else { return }
                isMagnifyingCanvas = false
                magnification = 1
                viewModel.endCanvasInteraction()
            }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Drop an image or folder here")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("⌘O open  \u{2022}  ⌘⇧I import from Photos  \u{2022}  ⌘⌥I source folder")
                .font(.caption)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
    }

    // MARK: - Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    viewModel.openSourceFolder(url: url)
                } else {
                    viewModel.collection.clear()
                    viewModel.openImage(url: url)
                }
            }
        }
        return true
    }
}

struct ComparisonBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            .foregroundColor(.primary)
    }
}
