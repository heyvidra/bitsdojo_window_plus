// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "bitsdojo_window_macos",
    platforms: [
        .macOS(.v10_14)
    ],
    products: [
        .library(name: "bitsdojo-window-macos", targets: ["bitsdojo_window_macos"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "bitsdojo_window_macos_objc",
            dependencies: [],
            path: "Sources/bitsdojo_window_macos_objc",
            publicHeadersPath: "include"
        ),
        .target(
            name: "bitsdojo_window_macos",
            dependencies: ["bitsdojo_window_macos_objc"],
            path: "Sources/bitsdojo_window_macos"
        )
    ]
)
