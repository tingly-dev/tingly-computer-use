import ApplicationServices
import Foundation
import ImageIO

/// Combined app state snapshot (AX tree + screenshot + metadata).
public struct AppStateSnapshot {
    public let pid: pid_t
    public let appName: String
    public let accessibilityTree: String
    public let screenshotPNG: Data
    /// Window bounds in Quartz screen coordinates (logical points, y-down from top-left of primary display).
    public let windowBounds: CGRect
    /// Screenshot dimensions in actual pixels (Retina may be 2x window bounds).
    public let screenshotPixelSize: CGSize
    /// Elements indexed by their string index for action lookups.
    public let elements: [String: AccessibilitySnapshot.Element]
}

/// Builds an AppStateSnapshot by running AX traversal and screenshot concurrently.
public enum AppSnapshotBuilder {

    public static func build(pid: pid_t, app: String) async throws -> AppStateSnapshot {
        // Run AX snapshot and screenshot truly concurrently.
        async let axResult = buildAX(pid: pid, app: app)
        async let screenshotResult = WindowCapture.capture(pid: pid)

        let (ax, png) = try await (axResult, screenshotResult)

        let pixelSize = pngPixelSize(png)

        return AppStateSnapshot(
            pid: pid,
            appName: app,
            accessibilityTree: ax.tree,
            screenshotPNG: png,
            windowBounds: ax.windowBounds,
            screenshotPixelSize: pixelSize,
            elements: ax.elements
        )
    }

    // MARK: - Private

    private struct AXResult {
        let tree: String
        let windowBounds: CGRect
        let elements: [String: AccessibilitySnapshot.Element]
    }

    private static func buildAX(pid: pid_t, app: String) async throws -> AXResult {
        let ax = AccessibilitySnapshot()
        try ax.build(pid: pid)

        let tree = ax.render(appName: app, pid: pid)
        let windowBounds = AccessibilitySnapshot.windowBounds(
            app: AXUIElementCreateApplication(pid)
        ) ?? .zero

        let elementMap = Dictionary(
            ax.elements.map { ($0.index, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return AXResult(tree: tree, windowBounds: windowBounds, elements: elementMap)
    }

    /// Reads the pixel dimensions from PNG data without fully decoding the image.
    private static func pngPixelSize(_ data: Data) -> CGSize {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat else {
            return .zero
        }
        return CGSize(width: w, height: h)
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
