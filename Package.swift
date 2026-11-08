// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudioDiverger",
    platforms: [.macOS("14.2")],
    targets: [
        .executableTarget(
            name: "AudioDiverger",
            path: "Sources/AudioDiverger",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
