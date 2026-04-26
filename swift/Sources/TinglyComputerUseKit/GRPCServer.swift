import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2

/// The gRPC server listening on a Unix domain socket.
@available(macOS 15.0, *)
public final class ComputerUseGRPCServer {
    private let socketPath: String

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public func run() async throws {
        let service = ComputerUseServiceImpl()

        // Local Unix socket — relax client keepalive restrictions so the Go gRPC
        // client's default HTTP/2 PING frames don't trigger ENHANCE_YOUR_CALM / GOAWAY.
        var transportConfig = HTTP2ServerTransport.Posix.Config.defaults
        transportConfig.connection.keepalive.clientBehavior = .init(
            minPingIntervalWithoutCalls: .seconds(1),
            allowWithoutCalls: true
        )

        let server = GRPCServer(
            transport: .http2NIOPosix(
                address: .unixDomainSocket(path: socketPath),
                transportSecurity: .plaintext,
                config: transportConfig
            ),
            services: [service]
        )

        try await withThrowingDiscardingTaskGroup { group in
            group.addTask { try await server.serve() }
            // Wait until the server is actually listening before printing the ready message.
            if let _ = try await server.listeningAddress {
                fputs("[tingly-cu-native] listening on \(self.socketPath)\n", stderr)
            }
            // Suspend until the task group is cancelled (i.e., process is killed).
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(3600))
            }
        }
    }
}
