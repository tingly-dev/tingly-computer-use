import AppKit
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

        // Initialize AppKit/CoreGraphics session — required for ScreenCaptureKit,
        // CGEvent, and any Quartz Window Services API (CGS_REQUIRE_INIT).
        await MainActor.run { _ = NSApplication.shared }

        // Remove stale socket file if it exists.
        try? FileManager.default.removeItem(atPath: socketPath)

        Log.info("starting gRPC server", "socket", socketPath)

        do {
            let server = ComputerUseGRPCServer(socketPath: socketPath)
            try await server.run()
        } catch {
            Log.error("server exited with error", "error", "\(error)")
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
