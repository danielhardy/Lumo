import SwiftUI

/// A full-width inspector disclosure row.
///
/// The row is one keyboard-operable toggle, rather than a native disclosure whose hit target can
/// be limited to its chevron. Keeping the content outside the button also means nested sections
/// receive their own independent toggle action.
struct InspectorDisclosure<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    init(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self._isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                    Text(title)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Double-tap to \(isExpanded ? "collapse" : "expand")")
            .accessibilityAddTraits(.isToggle)
            .accessibilityRemoveTraits(.isButton)

            if isExpanded {
                content()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggle() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
        }
    }
}
