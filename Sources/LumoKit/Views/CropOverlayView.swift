import CoreGraphics
import SwiftUI

/// The first crop tool is intentionally small and explicit: freeform framing only, no hidden
/// aspect-ratio lock, straighten, or rotation affordance. Coordinates are converted to the
/// normalized bottom-left model space before they reach AppViewModel.
struct CropOverlayView: View {
    enum Handle: CaseIterable, Hashable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }

    let normalizedRect: CGRect
    let imageSize: CGSize
    let onChange: (CGRect) -> Void
    let onApply: () -> Void
    let onReset: () -> Void
    let onCancel: () -> Void

    @State private var moveStart: CGRect?
    @State private var handleStarts: [Handle: CGRect] = [:]

    var body: some View {
        GeometryReader { geometry in
            let imageRect = fittedImageRect(in: geometry.size)
            let cropRect = screenRect(for: normalizedRect, in: imageRect)

            ZStack(alignment: .top) {
                dimmedOutside(cropRect: cropRect, in: geometry.size)

                Rectangle()
                    .fill(.clear)
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)
                    .contentShape(Rectangle())
                    .gesture(moveGesture(imageRect: imageRect))

                cropGuides(cropRect: cropRect)
                    .allowsHitTesting(false)

                ForEach(Handle.allCases, id: \.self) { handle in
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                        .frame(width: 18, height: 18)
                        .position(handlePosition(handle, in: cropRect))
                        .contentShape(Circle().scale(2))
                        .gesture(handleGesture(handle, imageRect: imageRect))
                        .accessibilityLabel("Crop \(handle.label) handle")
                        .accessibilityHint("Drag to resize the crop")
                }

                HStack(spacing: 8) {
                    Text("Crop")
                        .font(.headline)
                    Spacer()
                    Button("Reset", action: onReset)
                    Button("Cancel", action: onCancel)
                    Button("Apply", action: onApply)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(12)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Freeform crop")
            .accessibilityHint("Drag the crop handles within the image bounds")
            .onExitCommand(perform: onCancel)
        }
    }

    private func fittedImageRect(in viewport: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              viewport.width > 0, viewport.height > 0 else { return .zero }
        let scale = min(viewport.width / imageSize.width, viewport.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (viewport.width - size.width) / 2,
            y: (viewport.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func screenRect(for rect: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + rect.minX * imageRect.width,
            y: imageRect.minY + (1 - rect.maxY) * imageRect.height,
            width: rect.width * imageRect.width,
            height: rect.height * imageRect.height
        )
    }

    private func dimmedOutside(cropRect: CGRect, in size: CGSize) -> some View {
        Canvas { context, _ in
            var path = Path()
            path.addRect(CGRect(origin: .zero, size: size))
            path.addRect(cropRect)
            context.fill(path, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
    }

    private func cropGuides(cropRect: CGRect) -> some View {
        ZStack {
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
            Path { path in
                path.move(to: CGPoint(x: cropRect.width / 3, y: 0))
                path.addLine(to: CGPoint(x: cropRect.width / 3, y: cropRect.height))
                path.move(to: CGPoint(x: cropRect.width * 2 / 3, y: 0))
                path.addLine(to: CGPoint(x: cropRect.width * 2 / 3, y: cropRect.height))
                path.move(to: CGPoint(x: 0, y: cropRect.height / 3))
                path.addLine(to: CGPoint(x: cropRect.width, y: cropRect.height / 3))
                path.move(to: CGPoint(x: 0, y: cropRect.height * 2 / 3))
                path.addLine(to: CGPoint(x: cropRect.width, y: cropRect.height * 2 / 3))
            }
            .stroke(Color.white.opacity(0.6), lineWidth: 1)
        }
        .frame(width: cropRect.width, height: cropRect.height)
        .position(x: cropRect.midX, y: cropRect.midY)
    }

    private func handlePosition(_ handle: Handle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeading: return CGPoint(x: rect.minX, y: rect.minY)
        case .topTrailing: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeading: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomTrailing: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private func moveGesture(imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = moveStart ?? normalizedRect
                moveStart = start
                onChange(CropOverlayInteraction.translated(
                    start, delta: value.translation, imageRect: imageRect
                ))
            }
            .onEnded { _ in moveStart = nil }
    }

    private func handleGesture(_ handle: Handle, imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = handleStarts[handle] ?? normalizedRect
                handleStarts[handle] = start
                onChange(resized(start, handle: handle, delta: value.translation, imageRect: imageRect))
            }
            .onEnded { _ in handleStarts[handle] = nil }
    }

    private func resized(_ rect: CGRect, handle: Handle, delta: CGSize, imageRect: CGRect) -> CGRect {
        guard imageRect.width > 0, imageRect.height > 0 else { return rect }
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
}

/// Normalized crop movement is kept separate from SwiftUI gesture delivery so its bottom-left
/// coordinate conversion and image-bound clamping can be tested without a live view hierarchy.
enum CropOverlayInteraction {
    static func translated(_ rect: CGRect, delta: CGSize, imageRect: CGRect) -> CGRect {
        guard imageRect.width > 0, imageRect.height > 0 else { return rect }
        let dx = delta.width / imageRect.width
        let dy = -delta.height / imageRect.height
        return rect.offsetBy(
            dx: min(max(dx, -rect.minX), 1 - rect.maxX),
            dy: min(max(dy, -rect.minY), 1 - rect.maxY)
        )
    }
}

private extension CropOverlayView.Handle {
    var label: String {
        switch self {
        case .topLeading: return "top left"
        case .topTrailing: return "top right"
        case .bottomLeading: return "bottom left"
        case .bottomTrailing: return "bottom right"
        }
    }
}
