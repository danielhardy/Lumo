// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LUTzy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LUTzy",
            path: "LUTzy",
            exclude: ["Assets.xcassets", "LUTzy.entitlements"],
            linkerSettings: [
                .linkedFramework("PhotosUI"),
            ]
        ),
    ]
)
