// swift-tools-version: 6.0
import PackageDescription

// Lumo is split into a library plus a thin `@main` executable so the app's own
// code can be unit-tested: `@testable` cannot import an executable target.
// Everything of substance lives in LumoKit; the Lumo target is just the entry
// point, the app delegate, and the asset catalog.
let package = Package(
    name: "Lumo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Lumo", targets: ["Lumo"]),
        .library(name: "LumoKit", targets: ["LumoKit"]),
    ],
    targets: [
        .target(
            name: "LumoKit",
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                .linkedFramework("Photos"),
                .linkedFramework("PhotosUI"),
            ]
        ),
        .executableTarget(
            name: "Lumo",
            dependencies: ["LumoKit"],
            exclude: ["Assets.xcassets", "Lumo.entitlements"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LumoKitTests",
            dependencies: ["LumoKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
