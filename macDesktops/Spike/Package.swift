// swift-tools-version: 6.0
import PackageDescription

// U1 de-risk spike for "Parallel Project Desktops".
// THROWAWAY: this is not the shipped app — it exists only to answer the plan's
// U1 decision-gate questions on real hardware. See SPIKE.md.
//
// Language mode v5 keeps the spike free of Swift 6 strict-concurrency ceremony
// (global run-loop state, NSWorkspace observer) that would add noise without
// changing what the spike proves.
let package = Package(
    name: "spike",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "spike",
            path: "Sources/spike",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
