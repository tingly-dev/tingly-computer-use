import AppKit
import ApplicationServices

/// Discovers running and recently used applications.
public final class AppDiscovery {
    nonisolated(unsafe) public static let shared = AppDiscovery()
    private init() {}

    /// Returns all running apps + recently used apps (last 14 days).
    public func listApps() -> [AppInfo] {
        var apps: [AppInfo] = []

        // Running apps via NSWorkspace
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  let name = app.localizedName else { continue }
            apps.append(AppInfo(
                name: name,
                bundleID: app.bundleIdentifier ?? "",
                isRunning: true,
                daysSinceUsed: 0
            ))
        }

        // TODO: recently used apps via NSWorkspace recents or LaunchServices
        // For Phase 1, return running apps only.

        return apps.sorted { $0.name < $1.name }
    }

    /// Resolves a PID for the given app name or bundle identifier.
    /// Throws ComputerUseError.appNotFound if no matching running app is found.
    public func resolvePID(app: String) throws -> pid_t {
        for running in NSWorkspace.shared.runningApplications {
            guard running.activationPolicy == .regular else { continue }
            let nameMatch = running.localizedName?.lowercased() == app.lowercased()
            let bundleMatch = running.bundleIdentifier?.lowercased() == app.lowercased()
            if nameMatch || bundleMatch {
                return running.processIdentifier
            }
        }
        throw ComputerUseError.appNotFound(app)
    }
}

public struct AppInfo {
    public let name: String
    public let bundleID: String
    public let isRunning: Bool
    public let daysSinceUsed: Int32
}
