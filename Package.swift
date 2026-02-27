// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tachy",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Tachy",
            path: "Tachy",
            exclude: ["Info.plist", "Tachy.entitlements"]
        )
    ]
)
