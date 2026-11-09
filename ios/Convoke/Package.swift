// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ConvokeCore",
    platforms: [.iOS("26.0"), .macOS(.v13)],
    products: [.library(name: "ConvokeCore", targets: ["ConvokeCore"])],
    targets: [
        .target(name: "ConvokeCore", path: "Core"),
        .testTarget(
            name: "ConvokeCoreTests", dependencies: ["ConvokeCore"], path: ".",
            exclude: ["Core", "App/ContentView.swift",
                      "App/ConvokeApp.swift", "App/Info.plist", "Convoke.xcodeproj",
                      "README.md", "project.yml"],
            sources: ["Tests", "App/WebSocketTransport.swift", "App/AppleSpeechCapture.swift", "App/PCMPlayer.swift"]
        )
    ]
)
