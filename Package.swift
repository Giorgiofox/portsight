// swift-tools-version: 5.9
import PackageDescription

// CablePro — personal USB-C cable diagnostics for Apple Silicon.
//
// Reuses the MIT-licensed data layer from WhatCable
// (WhatCableCore / WhatCableDarwinBackend / WhatCableAppKit) verbatim.
// See LICENSE-whatcable and NOTICE.md for attribution.
// The proprietary WhatCablePlugins module is NOT used or included.

let package = Package(
    name: "CablePro",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "cablepro", targets: ["CableProCLI"]),
        .executable(name: "CablePro", targets: ["CablePro"]),
    ],
    targets: [
        // ── Reused MIT layer (unmodified) ──────────────────────────────
        .target(
            name: "WhatCableCore",
            path: "Sources/WhatCableCore",
            resources: [.process("Resources")]
        ),
        .target(
            name: "WhatCableDarwinBackend",
            dependencies: ["WhatCableCore"],
            path: "Sources/WhatCableDarwinBackend"
        ),
        .target(
            name: "WhatCableAppKit",
            dependencies: ["WhatCableCore"],
            path: "Sources/WhatCableAppKit"
        ),

        // ── Our own code ───────────────────────────────────────────────
        .executableTarget(
            name: "CableProCLI",
            dependencies: ["WhatCableCore", "WhatCableDarwinBackend"],
            path: "Sources/CableProCLI"
        ),
        .target(
            name: "CableProUI",
            dependencies: ["WhatCableCore", "WhatCableDarwinBackend"],
            path: "Sources/CableProUI"
        ),
        .executableTarget(
            name: "CablePro",
            dependencies: ["CableProUI"],
            path: "Sources/CablePro"
        ),
        .executableTarget(
            name: "CableProPreview",
            dependencies: ["CableProUI", "WhatCableCore"],
            path: "Sources/CableProPreview"
        ),
    ]
)
