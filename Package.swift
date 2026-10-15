// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Usami",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Usami",
            path: "Sources/Usami"
        )
    ]
)
