import Foundation
import CoreGraphics
import ApplicationServices

/// Simulates mouse and keyboard input using CoreGraphics events.
/// Strategy: AX semantic actions first → postToPid targeted → global fallback (env opt-in).
public enum InputSimulator {

    // MARK: - Click

    public static func click(pid: pid_t, elementIndex: String?, x: Double?, y: Double?,
                             snapshot: AppStateSnapshot?, clickCount: Int,
                             button: MouseButtonKind) async throws {
        // 1. Try AX semantic action if element index is provided.
        if let idx = elementIndex, let snap = snapshot, let el = snap.elements[idx] {
            if tryAXPress(element: el) { return }
        }

        // 2. Resolve click point in window-local logical coords.
        let localPoint = try resolveClickPoint(
            elementIndex: elementIndex, x: x, y: y, snapshot: snapshot
        )

        // 3. Convert to global Quartz screen coordinates.
        let wb = snapshot?.windowBounds ?? .zero
        let global = toGlobalPoint(point: localPoint, windowBounds: wb)

        // 4. Post targeted mouse events to PID.
        postMouseClick(pid: pid, point: global, button: button, clickCount: clickCount)
    }

    // MARK: - Type Text

    public static func typeText(pid: pid_t, text: String) async throws {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        for scalar in text.unicodeScalars {
            var chars = [UniChar(scalar.value & 0xFFFF)]
            event.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            event.postToPid(pid)
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms between chars
        }
    }

    // MARK: - Press Key

    public static func pressKey(pid: pid_t, key: String) async throws {
        let parsed = KeyParser.parse(key)
        // Send modifier down events.
        for mod in parsed.modifiers {
            postKeyEvent(pid: pid, keyCode: mod, down: true)
        }
        // Send main key.
        postKeyEvent(pid: pid, keyCode: parsed.keyCode, down: true)
        postKeyEvent(pid: pid, keyCode: parsed.keyCode, down: false)
        // Release modifiers in reverse.
        for mod in parsed.modifiers.reversed() {
            postKeyEvent(pid: pid, keyCode: mod, down: false)
        }
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms post-delay
    }

    // MARK: - Scroll

    public static func scroll(pid: pid_t, elementIndex: String, snapshot: AppStateSnapshot?,
                              direction: ScrollDirectionKind, pages: Double) async throws {
        let localPoint = try resolveElementCenter(elementIndex: elementIndex, snapshot: snapshot)
        let wb = snapshot?.windowBounds ?? .zero
        let global = toGlobalPoint(point: localPoint, windowBounds: wb)

        let delta = Int32(max(1, Int32(exactly: (12.0 * pages).rounded()) ?? 12))

        let (wheel1, wheel2): (Int32, Int32)
        switch direction {
        case .up:    (wheel1, wheel2) = (delta, 0)
        case .down:  (wheel1, wheel2) = (-delta, 0)
        case .left:  (wheel1, wheel2) = (0, delta)
        case .right: (wheel1, wheel2) = (0, -delta)
        }

        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                  wheelCount: 2, wheel1: wheel1, wheel2: wheel2, wheel3: 0) else {
            throw ComputerUseError.inputFailed("scroll event creation failed")
        }
        event.location = global
        event.postToPid(pid)
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    // MARK: - Drag

    public static func drag(pid: pid_t, fromX: Double, fromY: Double,
                            toX: Double, toY: Double,
                            snapshot: AppStateSnapshot?) async throws {
        let wb = snapshot?.windowBounds ?? .zero
        let from = toGlobalPoint(point: CGPoint(x: fromX, y: fromY), windowBounds: wb)
        let to   = toGlobalPoint(point: CGPoint(x: toX,   y: toY),   windowBounds: wb)
        let steps = 10

        postMouseEvent(pid: pid, type: .mouseMoved,     point: from, button: .left)
        postMouseEvent(pid: pid, type: .leftMouseDown,  point: from, button: .left)

        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let mid = CGPoint(
                x: from.x + (to.x - from.x) * t,
                y: from.y + (to.y - from.y) * t
            )
            postMouseEvent(pid: pid, type: .leftMouseDragged, point: mid, button: .left)
        }
        postMouseEvent(pid: pid, type: .leftMouseUp, point: to, button: .left)
    }

    // MARK: - Secondary Action

    public static func performSecondaryAction(pid: pid_t, elementIndex: String,
                                              action: String,
                                              snapshot: AppStateSnapshot?) async throws {
        guard let snap = snapshot, let el = snap.elements[elementIndex] else {
            throw ComputerUseError.elementNotFound(elementIndex)
        }
        guard el.actions.contains(action) else {
            throw ComputerUseError.inputFailed(
                "Action \"\(action)\" not available on element \(elementIndex). " +
                "Available: \(el.actions.joined(separator: ", "))"
            )
        }
        let result = AXUIElementPerformAction(el.axElement, action as CFString)
        guard result == .success else {
            throw ComputerUseError.inputFailed(
                "AXUIElementPerformAction(\"\(action)\") failed with code \(result.rawValue)"
            )
        }
    }

    // MARK: - Set Value

    public static func setValue(pid: pid_t, elementIndex: String, value: String,
                                snapshot: AppStateSnapshot?) async throws {
        guard let snap = snapshot, let el = snap.elements[elementIndex] else {
            throw ComputerUseError.elementNotFound(elementIndex)
        }
        guard el.isSettable else {
            throw ComputerUseError.inputFailed(
                "Element \(elementIndex) (\(el.role)) does not have a settable value attribute."
            )
        }
        let result = AXUIElementSetAttributeValue(
            el.axElement, kAXValueAttribute as CFString, value as CFTypeRef
        )
        guard result == .success else {
            throw ComputerUseError.inputFailed(
                "AXUIElementSetAttributeValue failed with code \(result.rawValue)"
            )
        }
    }

    // MARK: - Helpers

    /// Try AX semantic action (AXPress / AXConfirm / AXOpen) on the element.
    /// Returns true if an action was successfully performed.
    private static func tryAXPress(element: AccessibilitySnapshot.Element) -> Bool {
        for action in ["AXPress", "AXConfirm", "AXOpen"] {
            guard element.actions.contains(action) else { continue }
            let result = AXUIElementPerformAction(element.axElement, action as CFString)
            if result == .success { return true }
        }
        return false
    }

    /// Resolve a click target to window-local logical coordinates.
    /// Screenshot pixel coords are scaled down to logical points via the Retina scale factor.
    private static func resolveClickPoint(elementIndex: String?, x: Double?, y: Double?,
                                          snapshot: AppStateSnapshot?) throws -> CGPoint {
        // Element-index path: use center of element's AX frame (already window-local).
        if let idx = elementIndex, let snap = snapshot, let el = snap.elements[idx] {
            return CGPoint(x: el.frame.midX, y: el.frame.midY)
        }

        // Coordinate path: convert screenshot pixels → window-local logical points.
        guard let xv = x, let yv = y else {
            throw ComputerUseError.missingCoordinates
        }

        guard let snap = snapshot,
              snap.screenshotPixelSize.width > 0,
              snap.windowBounds.width > 0 else {
            // No snapshot context — treat as logical coords already.
            return CGPoint(x: xv, y: yv)
        }

        // Compute actual Retina scale factor from pixel vs. logical sizes.
        let scaleX = snap.screenshotPixelSize.width  / snap.windowBounds.width
        let scaleY = snap.screenshotPixelSize.height / snap.windowBounds.height
        return CGPoint(x: xv / scaleX, y: yv / scaleY)
    }

    private static func resolveElementCenter(elementIndex: String,
                                             snapshot: AppStateSnapshot?) throws -> CGPoint {
        guard let snap = snapshot, let el = snap.elements[elementIndex] else {
            throw ComputerUseError.elementNotFound(elementIndex)
        }
        return CGPoint(x: el.frame.midX, y: el.frame.midY)
    }

    private static func toGlobalPoint(point: CGPoint, windowBounds: CGRect) -> CGPoint {
        CGPoint(x: windowBounds.origin.x + point.x,
                y: windowBounds.origin.y + point.y)
    }

    private static func postMouseClick(pid: pid_t, point: CGPoint, button: MouseButtonKind,
                                       clickCount: Int) {
        let (downType, upType): (CGEventType, CGEventType)
        let cgButton: CGMouseButton
        switch button {
        case .right:
            (downType, upType) = (.rightMouseDown, .rightMouseUp)
            cgButton = .right
        case .middle:
            (downType, upType) = (.otherMouseDown, .otherMouseUp)
            cgButton = .center
        default:
            (downType, upType) = (.leftMouseDown, .leftMouseUp)
            cgButton = .left
        }

        postMouseEvent(pid: pid, type: .mouseMoved, point: point, button: cgButton)
        for _ in 0..<clickCount {
            postMouseEvent(pid: pid, type: downType, point: point, button: cgButton)
            postMouseEvent(pid: pid, type: upType,   point: point, button: cgButton)
        }
    }

    private static func postMouseEvent(pid: pid_t, type: CGEventType, point: CGPoint,
                                       button: CGMouseButton) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: button) else { return }
        event.postToPid(pid)
    }

    private static func postKeyEvent(pid: pid_t, keyCode: CGKeyCode, down: Bool) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else { return }
        event.postToPid(pid)
    }
}
