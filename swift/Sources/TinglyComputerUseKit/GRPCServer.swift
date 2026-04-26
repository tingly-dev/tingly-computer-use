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

        let server = GRPCServer(
            transport: .http2NIOPosix(
                address: .unixDomainSocket(path: socketPath),
                transportSecurity: .plaintext
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
