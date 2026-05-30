# LUTzy for macOS

A native macOS app for applying .cube LUTs to RAW/DNG and standard image files.
Built with SwiftUI and Core Image — zero dependencies.

## Features

- **Native RAW support** — DNG, CR2, CR3, NEF, ARW, and more via Core Image's CIRAWFilter
- **GPU-accelerated LUTs** — .cube files applied via Metal-backed CIColorCube
- **Sidebar LUT browser** — scans your LUT folder, grouped by subfolder
- **Live preview** — click any LUT and see the result instantly
- **Hold Space to compare** — toggles back to the original while held
- **Drag and drop** — drop a RAW file onto the window to open it
- **Keyboard shortcuts** — ←→ cycle LUTs, ⌘O open, ⌘S export, ⌘⇧L choose LUT folder
- **Export** — TIFF (16-bit), JPEG, or PNG at full resolution
- **App Sandbox ready** — uses security-scoped bookmarks for folder access

## Project Setup in Xcode

1. **Open Xcode** → File → New → Project
2. Choose **macOS → App**
3. Configure:
   - Product Name: **LUTzy**
   - Team: *(your team)*
   - Organization Identifier: e.g. `com.yourname`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - ✅ Include Tests (optional)
4. **Delete** the auto-generated `ContentView.swift` and `Assets.xcassets`
5. **Drag the contents of the `LUTzy/` folder** from this project into the Xcode project navigator
   - Make sure "Copy items if needed" is checked
   - Add to target: LUTzy
6. In project settings:
   - Set **Deployment Target** to **macOS 14.0** (for `.onKeyPress`)
   - Under **Signing & Capabilities**, add **App Sandbox** if not already present
   - Replace the entitlements file with the included `LUTzy.entitlements`
7. **Build and run** (⌘R)

## Project Structure

```
LUTzy/
├── LUTzyApp.swift              # App entry point, window + menu commands
├── Models/
│   ├── CubeLUT.swift           # .cube parser → CIColorCube filter
│   ├── ImageProcessor.swift    # RAW loading, preview rendering, export
│   └── LUTLibrary.swift        # Scans LUT folder, groups by category
├── ViewModels/
│   └── AppViewModel.swift      # Central state: image, LUT, preview
├── Views/
│   ├── ContentView.swift       # Main layout: sidebar + preview + status
│   ├── LUTSidebar.swift        # Sidebar with search and grouped LUTs
│   └── PreviewView.swift       # Image canvas with drag-drop + badges
├── Assets.xcassets/            # App icon + accent color
└── LUTzy.entitlements          # Sandbox + file access permissions
```

## Architecture Notes

- **Core Image** handles everything: RAW demosaicing (`CIRAWFilter`), LUT application
  (`CIColorCubeWithColorSpace`), and export. All GPU-accelerated via Metal.
- **No third-party dependencies** — ships with just Apple frameworks.
- The LUT folder path is persisted as a **security-scoped bookmark** so it survives
  app restarts under App Sandbox.
- Preview rendering is capped at 1600×1200 for responsiveness; export is always
  full resolution.

## Preparing for App Store

1. Add an app icon (1024×1024 source image → drag into `AppIcon.appiconset`)
2. Set your **Bundle Identifier** in Xcode project settings
3. Configure **Signing** with your Apple Developer certificate
4. Product → Archive → Distribute App → App Store Connect
