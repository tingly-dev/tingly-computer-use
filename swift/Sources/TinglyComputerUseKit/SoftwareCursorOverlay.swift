import AppKit
import Foundation

/// Minimal software cursor overlay — an NSWindow with a cursor glyph image
/// that floats above the target app window. Cleared on turn-ended.
public final class SoftwareCursorOverlay {
    nonisolated(unsafe) public static let shared = SoftwareCursorOverlay()
    private var window: NSWindow?
    private var isVisible = false

    private init() {}

    /// Move the visual cursor to a point in screen coordinates.
    public func moveTo(point: CGPoint) {
        ensureWindow()
        guard let win = window else { return }
        // AppKit uses y-up coordinates; convert from Quartz y-down.
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let appKitPoint = NSPoint(x: point.x - 16, y: screenHeight - point.y - 16)
        win.setFrameOrigin(appKitPoint)
        if !isVisible {
            win.orderFront(nil)
            isVisible = true
        }
    }

    /// Hide and clear the cursor overlay (call on turn-ended).
    public func hide() {
        window?.orderOut(nil)
        isVisible = false
    }

    private func ensureWindow() {
        guard window == nil else { return }
        let size = NSSize(width: 32, height: 32)
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.level = .floating
        win.isOpaque = false
        win.backgroundColor = .clear
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Draw a simple pointer shape.
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = cursorImage(size: size)
        win.contentView = imageView

        window = win
    }

    private func cursorImage(size: NSSize) -> NSImage {
        return NSImage(size: size, flipped: false) { rect in
            NSColor.black.withAlphaComponent(0.8).setFill()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 4, y: rect.height - 4))
            path.line(to: NSPoint(x: 4, y: 4))
            path.line(to: NSPoint(x: 14, y: 14))
            path.line(to: NSPoint(x: 10, y: 16))
            path.line(to: NSPoint(x: 18, y: 28))
            path.line(to: NSPoint(x: 14, y: 30))
            path.line(to: NSPoint(x: 6, y: 18))
            path.line(to: NSPoint(x: 4, y: rect.height - 4))
            path.fill()
            return true
        }
    }
}
