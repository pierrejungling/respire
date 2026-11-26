// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Respire",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Respire",
            path: "Sources/Respire",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
            ]
        )
    ]
)
