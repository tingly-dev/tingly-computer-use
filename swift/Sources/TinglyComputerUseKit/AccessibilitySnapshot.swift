import ApplicationServices
import Foundation

/// Traverses the accessibility tree of an app window and renders it as text.
public final class AccessibilitySnapshot {
    private static let maxDepth = 16
    private static let maxNodes = 500
    private static let maxVisibleRows = 20

    public struct Element {
        public let index: String
        public let role: String
        public let label: String
        public let value: String?
        public let isSettable: Bool
        public let actions: [String]
        /// Frame in window-local logical points.
        public let frame: CGRect
        public let depth: Int
        /// Live AX reference — used for semantic actions (AXPress, setValue, etc.).
        public let axElement: AXUIElement
        /// Identifier (e.g. "close", "minimize") — shown when no text label is available.
        public let identifier: String
        /// Role description (e.g. "close window button") from kAXRoleDescriptionAttribute.
        public let roleDescription: String
    }

    public private(set) var elements: [Element] = []
    public private(set) var focusedElementIndex: String?
    private var nodeCount = 0
    private var visitedHashes = Set<CFHashCode>()

    public init() {}

    /// Build snapshot from the app's focused window, falling back to the first available window.
    public func build(pid: pid_t) throws {
        elements = []
        nodeCount = 0
        visitedHashes = []

        let appElement = AXUIElementCreateApplication(pid)

        // Resolve a window: prefer focused, fall back to first available.
        guard let window = Self.resolveWindow(app: appElement) else {
            throw ComputerUseError.noWindow
        }

        // Get window bounds for coordinate normalization.
        guard let windowBounds = Self.bounds(of: window) else {
            throw ComputerUseError.noWindow
        }

        var focusedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        let focusedElement = focusedRef as! AXUIElement?

        traverse(element: window, depth: 0, windowBounds: windowBounds,
                 focusedElement: focusedElement)
    }

    private func traverse(element: AXUIElement, depth: Int, windowBounds: CGRect,
                          focusedElement: AXUIElement?) {
        guard depth <= Self.maxDepth, nodeCount < Self.maxNodes else { return }

        let hash = CFHash(element)
        guard visitedHashes.insert(hash).inserted else { return }

        let role = Self.stringAttr(element, kAXRoleAttribute) ?? "unknown"
        let label = Self.stringAttr(element, kAXDescriptionAttribute)
            ?? Self.stringAttr(element, kAXTitleAttribute)
            ?? Self.stringAttr(element, kAXLabelValueAttribute)
            ?? Self.stringAttr(element, kAXHelpAttribute)
            ?? ""
        let value = Self.stringAttr(element, kAXValueAttribute)
        let identifier = Self.stringAttr(element, kAXIdentifierAttribute) ?? ""
        let roleDescription = Self.stringAttr(element, kAXRoleDescriptionAttribute) ?? ""

        // Skip invisible wrappers.
        if isInvisibleWrapper(element: element, role: role, label: label, value: value, identifier: identifier) {
            traverseChildren(element: element, depth: depth, windowBounds: windowBounds,
                             focusedElement: focusedElement)
            return
        }

        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)

        var actionNames: [String] = []
        var actionsRef: CFArray?
        if AXUIElementCopyActionNames(element, &actionsRef) == .success,
           let names = actionsRef as? [String] {
            actionNames = names.filter { !["AXShowMenu", "AXScrollToVisible"].contains($0) }
        }

        let frame = Self.elementFrame(element: element, windowBounds: windowBounds)
        let index = String(nodeCount)
        nodeCount += 1

        let el = Element(
            index: index,
            role: role,
            label: label,
            value: value,
            isSettable: settable.boolValue,
            actions: actionNames,
            frame: frame,
            depth: depth,
            axElement: element,
            identifier: identifier,
            roleDescription: roleDescription
        )
        elements.append(el)

        if let focused = focusedElement, CFEqual(element, focused) {
            focusedElementIndex = index
        }

        traverseChildren(element: element, depth: depth, windowBounds: windowBounds,
                         focusedElement: focusedElement)
    }

    private func traverseChildren(element: AXUIElement, depth: Int, windowBounds: CGRect,
                                  focusedElement: AXUIElement?) {
        // Prefer children, fall back to rows for tables/outlines.
        let children = Self.axChildren(element) ?? Self.axRows(element) ?? []
        let limited = children.prefix(Self.maxVisibleRows)
        for child in limited {
            traverse(element: child, depth: depth + 1, windowBounds: windowBounds,
                     focusedElement: focusedElement)
        }
    }

    private func isInvisibleWrapper(element: AXUIElement, role: String, label: String,
                                    value: String?, identifier: String) -> Bool {
        guard role == "AXGroup" || role == "AXUnknown" else { return false }
        guard label.isEmpty, value == nil, identifier.isEmpty else { return false }
        let children = Self.axChildren(element) ?? []
        return children.count == 1
    }

    // MARK: - Rendering

    /// Render the snapshot as a human-readable tree string.
    public func render(appName: String, pid: pid_t) -> String {
        var lines: [String] = []
        lines.append("App=\(appName) (pid \(pid))")

        for el in elements {
            let indent = String(repeating: "    ", count: el.depth)
            var parts = [el.index, el.role]
            if !el.label.isEmpty {
                parts.append("\"\(el.label)\"")
            } else if !el.roleDescription.isEmpty {
                // Fall back to role description (e.g. "close window button")
                parts.append("[\(el.roleDescription)]")
            } else if !el.identifier.isEmpty {
                // Fall back to identifier (e.g. "close", "minimize")
                parts.append("[\(el.identifier)]")
            }
            if let v = el.value, !v.isEmpty {
                parts.append("value=\(v)")
            }
            if el.isSettable { parts.append("(settable)") }
            if !el.actions.isEmpty {
                parts.append("Secondary Actions: \(el.actions.joined(separator: ", "))")
            }
            lines.append(indent + parts.joined(separator: " "))
        }

        if let idx = focusedElementIndex {
            lines.append("\nThe focused UI element is \(idx).")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - AX Helpers

    static func stringAttr(_ element: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else {
            return nil
        }
        return ref as? String
    }

    static func axChildren(_ element: AXUIElement) -> [AXUIElement]? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
              let children = ref as? [AXUIElement], !children.isEmpty else { return nil }
        return children
    }

    static func axRows(_ element: AXUIElement) -> [AXUIElement]? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRowsAttribute as CFString, &ref) == .success,
              let rows = ref as? [AXUIElement], !rows.isEmpty else { return nil }
        return rows
    }

    static func elementFrame(element: AXUIElement, windowBounds: CGRect) -> CGRect {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var pos = CGPoint.zero
        var size = CGSize.zero

        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success {
            AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        }
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success {
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        }

        // Convert to window-local coordinates.
        return CGRect(
            x: pos.x - windowBounds.origin.x,
            y: pos.y - windowBounds.origin.y,
            width: size.width,
            height: size.height
        )
    }

    /// Returns the focused window for `app`, falling back to the first window in kAXWindowsAttribute.
    static func resolveWindow(app: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &ref) == .success,
           let window = ref as! AXUIElement? {
            return window
        }
        // Fall back to the first available window.
        var winRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &winRef) == .success,
           let windows = winRef as? [AXUIElement], let first = windows.first {
            return first
        }
        return nil
    }

    /// Returns the bounds of a specific window element.
    static func bounds(of window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var pos = CGPoint.zero
        var size = CGSize.zero

        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success {
            AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        }
        if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success {
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        }

        guard size != .zero else { return nil }
        return CGRect(origin: pos, size: size)
    }

    /// Returns the bounds of the focused (or first available) window for `app`.
    static func windowBounds(app: AXUIElement) -> CGRect? {
        guard let window = resolveWindow(app: app) else { return nil }
        return bounds(of: window)
    }
}
