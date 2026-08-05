// swift-tools-version: 5.9
import PackageDescription

// LUTzy is split into a library plus a thin `@main` executable so the app's own
// code can be unit-tested: `@testable` cannot import an executable target.
// Everything of substance lives in LUTzyKit; the LUTzy target is just the entry
// point, the app delegate, and the asset catalog.
let package = Package(
    name: "LUTzy",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LUTzy", targets: ["LUTzy"]),
        .library(name: "LUTzyKit", targets: ["LUTzyKit"]),
    ],
    targets: [
        .target(
            name: "LUTzyKit",
            linkerSettings: [
                .linkedFramework("PhotosUI"),
            ]
        ),
        .executableTarget(
            name: "LUTzy",
            dependencies: ["LUTzyKit"],
            exclude: ["Assets.xcassets", "LUTzy.entitlements"]
        ),
        .testTarget(
            name: "LUTzyKitTests",
            dependencies: ["LUTzyKit"]
        ),
    ]
)
