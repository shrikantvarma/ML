// swift-tools-version: 6.0
import PackageDescription

// Parallel Project Desktops — shipped app (v1 MVP foundation).
//
// Structure: a testable Core library (all logic + system wrappers behind
// protocols) + a thin SwiftUI executable + a test target. Language mode v5
// keeps the foundation free of strict-concurrency ceremony for now.
//
// Tooling note: this is a SwiftPM app for development. Signing/notarization
// (plan KTD-1) and an LSUIElement Info.plist are a later Xcode-migration step;
// no-Dock-icon behavior is achieved at runtime via setActivationPolicy(.accessory).
let package = Package(
    name: "ParallelDesktops",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ParallelDesktopsCore",
            path: "Sources/ParallelDesktopsCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ParallelDesktops",
            dependencies: ["ParallelDesktopsCore"],
            path: "Sources/ParallelDesktops",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ParallelDesktopsCoreTests",
            dependencies: ["ParallelDesktopsCore"],
            path: "Tests/ParallelDesktopsCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
