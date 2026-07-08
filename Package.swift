// swift-tools-version:5.9
//
// SwiftPM manifest — lets Xcode (and SourceKit-LSP) open the project with a full
// whole-module view: editing, autocomplete, and building/running the CLI + tests.
//
// This is an *additive* convenience: the Makefile + `swiftc` remain the source of
// truth for releases and Homebrew (the CLI formula builds via `make build`; the
// menu-bar cask ships the `.app` that `make gui` bundles — SwiftPM can't produce
// an `.app` bundle). The shared sensor code is a real module here, so the entry
// files `import MacThermalCore` behind a `#if canImport(...)` guard that the flat
// Makefile build (one module, no such import) simply compiles away.
//
// Pinned to tools 5.9 (Swift 5 language mode) on purpose: it matches the current
// `swiftc` build and avoids Swift 6 strict-concurrency errors in the GUI actor code.

import PackageDescription

let package = Package(
    name: "macthermal",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "macthermal", targets: ["macthermal"]),
        .executable(name: "macthermal-gui", targets: ["macthermal-gui"]),
    ],
    targets: [
        // Shared, UI-agnostic sensor core (IOKit/SMC, model, thresholds, JSON).
        .target(name: "MacThermalCore", path: "Sources/MacThermalCore"),

        // CLI front-end (top-level code in main.swift).
        .executableTarget(
            name: "macthermal",
            dependencies: ["MacThermalCore"],
            path: "Sources/macthermal"
        ),

        // Menu-bar front-end. `swift build` yields a bare executable; the runnable
        // `.app` bundle (Info.plist/LSUIElement/icon/signing) still comes from `make gui`.
        .executableTarget(
            name: "macthermal-gui",
            dependencies: ["MacThermalCore"],
            path: "Sources/macthermal-gui"
        ),

        // Standalone, XCTest-free logic runner (@main). Run: `swift run macthermalTests`.
        .executableTarget(
            name: "macthermalTests",
            dependencies: ["MacThermalCore"],
            path: "Tests"
        ),
    ]
)
