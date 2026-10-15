// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kairos",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "Kairos", path: "Sources/Kairos")
    ],
    swiftLanguageModes: [.v5]
)
