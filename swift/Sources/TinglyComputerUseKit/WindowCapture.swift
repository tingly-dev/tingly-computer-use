import Foundation
import ScreenCaptureKit
import AppKit

/// Captures a screenshot of a specific app window using ScreenCaptureKit.
public enum WindowCapture {

    /// Capture the key window of the app with the given PID.
    /// Returns PNG bytes at Retina resolution with cursor hidden.
    public static func capture(pid: pid_t) async throws -> Data {
        // Get shareable content.
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )

        // Find the best window for this PID.
        let windows = content.windows.filter { $0.owningApplication?.processID == pid }
        guard let window = selectBestWindow(from: windows) else {
            throw ComputerUseError.noWindow
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)

        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.scalesToFit = false
        config.ignoreShadowsSingleWindow = true

        // Match screen pixel density.
        let scale = screenScaleFactor(for: window)
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        return try pngData(from: cgImage)
    }

    // MARK: - Private

    private static func selectBestWindow(from windows: [SCWindow]) -> SCWindow? {
        // Prefer the largest on-screen window (key window heuristic).
        return windows
            .filter { $0.isOnScreen }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    private static func screenScaleFactor(for window: SCWindow) -> CGFloat {
        let windowCenter = CGPoint(
            x: window.frame.midX,
            y: window.frame.midY
        )
        for screen in NSScreen.screens {
            if screen.frame.contains(windowCenter) {
                return screen.backingScaleFactor
            }
        }
        return NSScreen.main?.backingScaleFactor ?? 2.0
    }

    private static func pngData(from image: CGImage) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ComputerUseError.screenshotFailed("PNG conversion failed")
        }
        return data
    }
}
