import Foundation

/// Errors thrown by tingly-computer-use.
public enum ComputerUseError: Error, LocalizedError {
    case appNotFound(String)
    case noWindow
    case elementNotFound(String)
    case missingCoordinates
    case screenshotFailed(String)
    case inputFailed(String)
    case permissionDenied(String)
    case notImplemented(String)

    public var errorDescription: String? {
        switch self {
        case .appNotFound(let app):
            return "App not found: \"\(app)\". Use list_apps to see available apps."
        case .noWindow:
            return "No accessible window found for the app."
        case .elementNotFound(let idx):
            return "Element \(idx) not found. Call get_app_state to refresh the element list."
        case .missingCoordinates:
            return "Either element_index or x/y coordinates are required."
        case .screenshotFailed(let msg):
            return "Screenshot failed: \(msg)"
        case .inputFailed(let msg):
            return "Input simulation failed: \(msg)"
        case .permissionDenied(let perm):
            return "Permission not granted: \(perm). Run 'tingly-cu-native doctor' to fix."
        case .notImplemented(let msg):
            return "Not implemented: \(msg)"
        }
    }
}

/// Version info.
public enum TinglyComputerUseVersion {
    public static let current = "0.1.0"
}
