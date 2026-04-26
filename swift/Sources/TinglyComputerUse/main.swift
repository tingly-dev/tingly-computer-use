import Foundation
import TinglyComputerUseKit

@main
struct TinglyComputerUseMain {
    static func main() async {
        let args = CommandLine.arguments.dropFirst()
        let cmd = args.first ?? "serve"

        switch cmd {
        case "serve":
            await runServe(args: Array(args.dropFirst()))
        case "doctor":
            await runDoctor()
        case "version":
            print(TinglyComputerUseVersion.current)
        default:
            fputs("error: unknown command \"\(cmd)\"; available: serve, doctor, version\n", stderr)
            exit(1)
        }
    }

    static func runServe(args: [String]) async {
        var socketPath = "/tmp/tingly-cu-\(getuid()).sock"

        // Parse --socket <path>
        var i = 0
        while i < args.count {
            if args[i] == "--socket", i + 1 < args.count {
                socketPath = args[i + 1]
                i += 2
            } else {
                i += 1
            }
        }

        // Remove stale socket file if it exists.
        try? FileManager.default.removeItem(atPath: socketPath)

        fputs("[tingly-cu-native] starting gRPC server on \(socketPath)\n", stderr)

        do {
            let server = ComputerUseGRPCServer(socketPath: socketPath)
            try await server.run()
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }
    }

    static func runDoctor() async {
        let checker = PermissionChecker()
        let result = checker.check()

        if result.accessibilityGranted {
            print("OK:   Accessibility")
        } else {
            print("FAIL: Accessibility — open \(result.accessibilitySettingsURL)")
        }
        if result.screenRecordingGranted {
            print("OK:   Screen Recording")
        } else {
            print("FAIL: Screen Recording — open \(result.screenRecordingSettingsURL)")
        }
    }
}
