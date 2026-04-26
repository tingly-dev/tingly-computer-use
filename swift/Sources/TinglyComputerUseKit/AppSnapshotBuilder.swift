import ApplicationServices
import Foundation

/// Combined app state snapshot (AX tree + screenshot + metadata).
public struct AppStateSnapshot {
    public let pid: pid_t
    public let appName: String
    public let accessibilityTree: String
    public let screenshotPNG: Data
    public let windowBounds: CGRect
    /// Elements indexed by their string index for action lookups.
    public let elements: [String: AccessibilitySnapshot.Element]
}

/// Builds an AppStateSnapshot by running AX traversal and screenshot in parallel.
public enum AppSnapshotBuilder {

    public static func build(pid: pid_t, app: String) async throws -> AppStateSnapshot {
        // Run AX snapshot and screenshot concurrently.
        async let axTask: AppStateSnapshot = buildAX(pid: pid, app: app)
        let snapshot = try await axTask
        return snapshot
    }

    private static func buildAX(pid: pid_t, app: String) async throws -> AppStateSnapshot {
        let ax = AccessibilitySnapshot()
        try ax.build(pid: pid)

        let tree = ax.render(appName: app, pid: pid)
        let windowBounds = AccessibilitySnapshot.windowBounds(
            app: AXUIElementCreateApplication(pid)
        ) ?? .zero

        // Take screenshot.
        let png = try await WindowCapture.capture(pid: pid)

        let elementMap = Dictionary(
            ax.elements.map { ($0.index, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return AppStateSnapshot(
            pid: pid,
            appName: app,
            accessibilityTree: tree,
            screenshotPNG: png,
            windowBounds: windowBounds,
            elements: elementMap
        )
    }
}

/// Per-turn in-memory cache of app snapshots. Keyed by app name (lowercased).
public final class AppSnapshotCache: @unchecked Sendable {
    private var cache: [String: AppStateSnapshot] = [:]

    public init() {}

    public func set(_ snapshot: AppStateSnapshot, app: String) {
        cache[app.lowercased()] = snapshot
    }

    public func get(app: String) -> AppStateSnapshot? {
        return cache[app.lowercased()]
    }

    public func clear() {
        cache.removeAll()
    }
}
