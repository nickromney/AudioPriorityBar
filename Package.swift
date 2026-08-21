// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AudioPriorityBarCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AudioPriorityBarCore", targets: ["AudioPriorityBarCore"])
    ],
    targets: [
        .target(
            name: "AudioPriorityBarCore",
            path: "AudioPriorityBar",
            exclude: [
                "Assets.xcassets",
                "Info.plist",
                "AudioPriorityBarApp.swift",
                "Services/AudioDeviceService.swift",
                "Services/LaunchAtLoginManager.swift",
                "Views"
            ],
            sources: [
                "Models/AudioDevice.swift",
                "Models/DeviceReorder.swift",
                "Models/Headphones.swift",
                "Services/PriorityManager.swift"
            ]
        ),
        .testTarget(
            name: "AudioPriorityBarCoreTests",
            dependencies: ["AudioPriorityBarCore"],
            path: "Tests/AudioPriorityBarCoreTests"
        )
    ]
)
