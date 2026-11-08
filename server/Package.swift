// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ConvokeServer",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ConvokeServer", targets: ["ConvokeServer"])],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/vapor/websocket-kit.git", from: "2.16.2"),
    ],
    targets: [
        .executableTarget(name: "ConvokeServer", dependencies: [
            .product(name: "Vapor", package: "vapor"),
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
            .product(name: "NIOWebSocket", package: "swift-nio"),
            .product(name: "WebSocketKit", package: "websocket-kit"),
        ]),
        .testTarget(name: "ConvokeServerTests", dependencies: [
            "ConvokeServer",
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOPosix", package: "swift-nio"),
            .product(name: "NIOEmbedded", package: "swift-nio"),
            .product(name: "NIOWebSocket", package: "swift-nio"),
            .product(name: "WebSocketKit", package: "websocket-kit"),
        ]),
    ]
)
