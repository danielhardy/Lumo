import SwiftUI

/// The photographer-facing global Light inspector.
///
/// Sections are native `DisclosureGroup`s so the full toolset stays in the docked inspector without
/// taking over the photo canvas. The view only talks to LightControl and AppViewModel value bindings;
/// Core Image never appears in the editing surface.
struct LightInspectorView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var toneSectionExpanded = true
    @State private var curveSectionExpanded = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                DisclosureGroup("Tone", isExpanded: $toneSectionExpanded) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(LightControl.allCases, id: \.self) { control in
                            controlRow(control)
                        }
                    }
                    .padding(.top, 10)
                }

                DisclosureGroup("Tone Curve", isExpanded: $curveSectionExpanded) {
                    ToneCurveEditor(viewModel: viewModel)
                        .padding(.top, 10)
                }
            }
            .padding(16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Light adjustments")
    }

    private var header: some View {
        HStack {
            Text("Light").font(.headline)
            Spacer()
            Button("Reset Light") { viewModel.resetAllLight() }
                .buttonStyle(.link)
                .disabled(!viewModel.hasLightAdjustments)
                .accessibilityHint("Reset all Light controls, including the tone curve")
        }
    }

    private func controlRow(_ control: LightControl) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(control.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .onTapGesture(count: 2) { viewModel.resetLight(control) }
                Spacer()
                Text(readout(for: control))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .onTapGesture(count: 2) { viewModel.resetLight(control) }
                    .accessibilityLabel(control.title)
                    .accessibilityValue(readout(for: control))
                Button {
                    viewModel.resetLight(control)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .help("Reset (control.title)")
                .accessibilityLabel("Reset (control.title)")
            }

            Slider(
                value: viewModel.lightBinding(for: control),
                in: control.range,
                onEditingChanged: { editing in
                    if editing { viewModel.beginPreviewInteraction() }
                    else { viewModel.endPreviewInteraction() }
                }
            )
            .accessibilityLabel(control.title)
            .accessibilityValue(readout(for: control))
        }
    }

    private func readout(for control: LightControl) -> String {
        let value = viewModel.lightValue(for: control)
        switch control {
        case .exposure:
            return String(format: "%+.2f EV", value)
        case .contrast, .highlights, .shadows, .whites, .blacks:
            return String(format: "%+.0f", value)
        }
    }
}

/// A compact master RGB curve editor. The endpoint handles are fixed by `LightToneCurve`; interior
/// handles can be dragged and adjusted through the keyboard/VoiceOver adjustable action.
private struct ToneCurveEditor: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var draggingInput: Double?

    private let graphHeight: CGFloat = 190

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Master RGB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add Point") {
                    viewModel.addToneCurvePoint(input: 0.5, output: 0.5)
                }
                .buttonStyle(.link)
                Button("Reset") { viewModel.resetToneCurve() }
                    .buttonStyle(.link)
                    .disabled(viewModel.document.light.toneCurve.isIdentity)
            }

            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    curveGraph(size: size)
                    ForEach(editablePoints, id: \.input) { point in
                        pointHandle(point, size: size)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Master RGB tone curve")
            }
            .frame(height: graphHeight)

            HStack {
                Text("Shadows")
                Spacer()
                Text("Highlights")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var editablePoints: [LightCurvePoint] {
        let points = viewModel.document.light.toneCurve.points
        let interior = Array(points.dropFirst().dropLast())
        return interior.isEmpty
            ? [LightCurvePoint(input: 0.5, output: viewModel.document.light.toneCurve.value(at: 0.5))]
            : interior
    }

    private func curveGraph(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(.black.opacity(0.2)))

            var grid = Path()
            for fraction in stride(from: 0.25, through: 0.75, by: 0.25) {
                grid.move(to: CGPoint(x: fraction * canvasSize.width, y: 0))
                grid.addLine(to: CGPoint(x: fraction * canvasSize.width, y: canvasSize.height))
                grid.move(to: CGPoint(x: 0, y: (1 - fraction) * canvasSize.height))
                grid.addLine(to: CGPoint(x: canvasSize.width, y: (1 - fraction) * canvasSize.height))
            }
            context.stroke(grid, with: .color(.white.opacity(0.1)), lineWidth: 1)

            var identity = Path()
            identity.move(to: CGPoint(x: 0, y: canvasSize.height))
            identity.addLine(to: CGPoint(x: canvasSize.width, y: 0))
            context.stroke(identity, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            let curve = viewModel.document.light.toneCurve
            var path = Path()
            for index in 0...64 {
                let input = Double(index) / 64
                let point = CGPoint(
                    x: input * canvasSize.width,
                    y: (1 - curve.value(at: input)) * canvasSize.height
                )
                if index == 0 { path.move(to: point) }
                else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2))
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func pointHandle(_ point: LightCurvePoint, size: CGSize) -> some View {
        Button(action: {}) {
            Circle()
                .fill(Color.accentColor)
                .overlay(Circle().stroke(.white, lineWidth: 1))
                .frame(width: 12, height: 12)
                .shadow(radius: 1)
        }
        .buttonStyle(.plain)
        .position(position(for: point, in: size))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let input = min(max(value.location.x / max(size.width, 1), 0.001), 0.999)
                    let output = min(max(1 - value.location.y / max(size.height, 1), 0), 1)
                    let sourceInput = draggingInput ?? point.input
                    viewModel.moveToneCurvePoint(fromInput: sourceInput, input: input, output: output)
                    draggingInput = input
                }
                .onEnded { _ in draggingInput = nil }
        )
        .focusable()
        .accessibilityLabel("Tone curve point")
        .accessibilityValue(String(format: "Input %.2f, output %.2f", point.input, point.output))
        .accessibilityHint("Drag or use adjustment keys to change this point")
        .accessibilityAdjustableAction { direction in
            let step = 0.01
            let output: Double
            switch direction {
            case .increment: output = min(point.output + step, 1)
            case .decrement: output = max(point.output - step, 0)
            @unknown default: return
            }
            viewModel.setToneCurvePoint(point, output: output)
        }
    }

    private func position(for point: LightCurvePoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.input * size.width, y: (1 - point.output) * size.height)
    }
}
