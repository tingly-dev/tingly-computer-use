import ApplicationServices
import CoreGraphics
import Foundation
import SQLite3

/// Checks and guides users through required macOS permissions.
public final class PermissionChecker {

    public struct Result {
        public let accessibilityGranted: Bool
        public let screenRecordingGranted: Bool
        public let accessibilitySettingsURL: String
        public let screenRecordingSettingsURL: String

        public var allGranted: Bool {
            accessibilityGranted && screenRecordingGranted
        }
    }

    public init() {}

    public func check() -> Result {
        return Result(
            accessibilityGranted: checkAccessibility(),
            screenRecordingGranted: checkScreenRecording(),
            accessibilitySettingsURL:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            screenRecordingSettingsURL:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }

    // MARK: - Accessibility

    private func checkAccessibility() -> Bool {
        // AXIsProcessTrusted() is the canonical check.
        // Use AXIsProcessTrusted() directly (no prompt) to avoid concurrency warning.
        return AXIsProcessTrusted()
    }

    // MARK: - Screen Recording

    private func checkScreenRecording() -> Bool {
        // CGPreflightScreenCaptureAccess is available on macOS 11+.
        return CGPreflightScreenCaptureAccess()
    }
}
