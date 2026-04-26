import CoreGraphics
import Foundation

/// Maps xdotool key syntax to CGKeyCode values.
public enum KeyParser {

    public struct ParsedKey {
        public let keyCode: CGKeyCode
        public let modifiers: [CGKeyCode]
    }

    // Common xdotool key names → CGKeyCode
    private static let keyTable: [String: CGKeyCode] = [
        "Return": 36, "KP_Enter": 76,
        "Tab": 48,
        "space": 49,
        "BackSpace": 51, "Delete": 51,
        "Escape": 53,
        "Left": 123, "Right": 124, "Down": 125, "Up": 126,
        "F1": 122, "F2": 120, "F3": 99, "F4": 118, "F5": 96,
        "F6": 97, "F7": 98, "F8": 100, "F9": 101, "F10": 109,
        "F11": 103, "F12": 111,
        "Home": 115, "End": 119,
        "Page_Up": 116, "Prior": 116,
        "Page_Down": 121, "Next": 121,
        "KP_0": 82, "KP_1": 83, "KP_2": 84, "KP_3": 85, "KP_4": 86,
        "KP_5": 87, "KP_6": 88, "KP_7": 89, "KP_8": 91, "KP_9": 92,
        "KP_Decimal": 65,
        "comma": 43, "period": 47, "slash": 44,
        "semicolon": 41, "apostrophe": 39, "bracketleft": 33, "bracketright": 30,
        "backslash": 42, "grave": 50, "minus": 27, "equal": 24,
    ]

    private static let modifierTable: [String: CGKeyCode] = [
        "super": 55, "meta": 55, "cmd": 55, "command": 55,
        "ctrl": 59, "control": 59,
        "shift": 56,
        "alt": 58, "option": 58,
    ]

    public static func parse(_ key: String) -> ParsedKey {
        let parts = key.split(separator: "+").map(String.init)
        var modifiers: [CGKeyCode] = []
        var mainKey = ""

        for (i, part) in parts.enumerated() {
            if i < parts.count - 1, let mod = modifierTable[part.lowercased()] {
                modifiers.append(mod)
            } else {
                mainKey = part
            }
        }

        let keyCode: CGKeyCode
        if let code = keyTable[mainKey] {
            keyCode = code
        } else if mainKey.count == 1, let scalar = mainKey.unicodeScalars.first {
            // Single ASCII character → use CGKeyCode from character.
            keyCode = asciiKeyCode(scalar.value)
        } else {
            keyCode = 0
        }

        return ParsedKey(keyCode: keyCode, modifiers: modifiers)
    }

    private static func asciiKeyCode(_ code: UInt32) -> CGKeyCode {
        // Simplified ASCII → key code mapping (lowercase letters + digits).
        switch code {
        case 97...122: // a-z
            let letterCodes: [CGKeyCode] = [
                0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46,
                45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6
            ]
            let idx = Int(code - 97)
            return idx < letterCodes.count ? letterCodes[idx] : 0
        case 48...57: // 0-9
            let digitCodes: [CGKeyCode] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25]
            let idx = Int(code - 48)
            return idx < digitCodes.count ? digitCodes[idx] : 0
        default:
            return 0
        }
    }
}
