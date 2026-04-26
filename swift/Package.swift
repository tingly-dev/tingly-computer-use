// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TinglyComputerUse",
    platforms: [
        .macOS(.v15),  // grpc-swift v2 generated code requires macOS 15+
    ],
    products: [
        .executable(name: "tingly-cu-native", targets: ["TinglyComputerUse"]),
        .library(name: "TinglyComputerUseKit", targets: ["TinglyComputerUseKit"]),
    ],
    dependencies: [
        // gRPC-Swift v2 core runtime
        .package(
            url: "https://github.com/grpc/grpc-swift",
            from: "2.2.0"
        ),
        // gRPC-Swift NIO transport (HTTP2 over Unix socket / TCP)
        .package(
            url: "https://github.com/grpc/grpc-swift-nio-transport",
            from: "1.0.0"
        ),
        // gRPC-Swift Protobuf serialization bridge
        .package(
            url: "https://github.com/grpc/grpc-swift-protobuf",
            from: "1.0.0"
        ),
        // swift-protobuf for proto message types
        .package(
            url: "https://github.com/apple/swift-protobuf",
            from: "1.28.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "TinglyComputerUse",
            dependencies: ["TinglyComputerUseKit"],
            path: "Sources/TinglyComputerUse"
        ),
        .target(
            name: "TinglyComputerUseKit",
            dependencies: [
                .product(name: "GRPCCore", package: "grpc-swift"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Sources/TinglyComputerUseKit"
        ),
    ]
)
