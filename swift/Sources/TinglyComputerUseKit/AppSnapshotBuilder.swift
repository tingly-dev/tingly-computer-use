import AppKit
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
        // Ensure the app has a visible, focused window before snapshotting.
        try await focusWindow(pid: pid)

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

    // MARK: - Window focus

    /// Ensures the app has a raised, focused window before snapshotting.
    /// If no window is currently focused, tries AX raise actions first, then
    /// falls back to NSRunningApplication.activate, waits, and retries.
    /// Throws `noWindow` only if the app has no windows at all after the attempt.
    private static func focusWindow(pid: pid_t) async throws {
        let appElement = AXUIElementCreateApplication(pid)

        // Fast path: already have a focused window — raise it to be safe.
        if let window = AccessibilitySnapshot.resolveWindow(app: appElement) {
            raiseWindow(window, pid: pid)
            return
        }

        // No window found: activate the app to trigger window creation/restore.
        if let runningApp = NSRunningApplication(processIdentifier: pid) {
            DispatchQueue.main.async {
                runningApp.activate(options: [.activateAllWindows])
            }
        } else {
            Log.warn("focusWindow: no NSRunningApplication", "pid", pid)
        }

        // Wait up to 5 s for a window to appear (20 × 0.25 s).
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(250))
            if let window = AccessibilitySnapshot.resolveWindow(app: appElement) {
                raiseWindow(window, pid: pid)
                // Brief pause for the window to fully render on screen.
                try await Task.sleep(for: .milliseconds(150))
                return
            }
        }

        throw ComputerUseError.noWindow
    }

    /// Attempts to raise and focus a window via AX actions (raise → main → focused).
    private static func raiseWindow(_ window: AXUIElement, pid: pid_t) {
        // Try kAXRaiseAction first.
        var actionsRef: CFArray?
        if AXUIElementCopyActionNames(window, &actionsRef) == .success,
           let actions = actionsRef as? [String],
           actions.contains(kAXRaiseAction as String) {
            if AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success { return }
        }

        // Try setting kAXMainAttribute.
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(window, kAXMainAttribute as CFString, &settable) == .success,
           settable.boolValue {
            if AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue) == .success { return }
        }

        // Try setting kAXFocusedAttribute.
        settable = false
        if AXUIElementIsAttributeSettable(window, kAXFocusedAttribute as CFString, &settable) == .success,
           settable.boolValue {
            _ = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
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
/// Thread-safe: concurrent gRPC handlers may read/write simultaneously.
public final class AppSnapshotCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: AppStateSnapshot] = [:]

    public init() {}

    public func set(_ snapshot: AppStateSnapshot, app: String) {
        lock.lock()
        defer { lock.unlock() }
        cache[app.lowercased()] = snapshot
    }

    public func get(app: String) -> AppStateSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return cache[app.lowercased()]
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
}
