import AppKit
import SwiftUI

/// Appearance-aware surfaces shared by the app shell.
///
/// AppKit's named NSColors are dynamic colors: SwiftUI resolves them against the
/// current window appearance, so they update when macOS changes between light and
/// dark mode while the window is open. Keep fixed dark colors out of these shell
/// surfaces; image-analysis canvases have their own explicitly scoped colors.
enum LumoTheme {
    static var windowBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var controlBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    /// Deliberately dark backdrop for histogram and tone-curve plots. The plot
    /// content uses bright/primary colors so the analysis remains readable in
    /// either system appearance without darkening its containing inspector.
    static let analysisBackground = Color.black.opacity(0.25)
    static let analysisBorder = Color.white.opacity(0.08)
    static let analysisGrid = Color.white.opacity(0.10)
    static let analysisReference = Color.white.opacity(0.25)
}
