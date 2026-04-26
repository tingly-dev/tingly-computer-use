import Foundation
import GRPCCore
import GRPCProtobuf

/// gRPC service implementation conforming to the generated SimpleServiceProtocol.
/// Each method validates input, delegates to the appropriate subsystem, and returns a proto response.
@available(macOS 15.0, *)
public struct ComputerUseServiceImpl: Computeruse_V1_ComputerUseService.SimpleServiceProtocol {

    private let snapshotCache = AppSnapshotCache()

    public init() {}

    // MARK: - Read-only tools

    public func listApps(
        request: Computeruse_V1_ListAppsRequest,
        context: GRPCCore.ServerContext
    ) async throws -> Computeruse_V1_ListAppsResponse {
        let apps = AppDiscovery.shared.listApps()
        var response = Computeruse_V1_ListAppsResponse()
        response.apps = apps.map { app in
            var info = Computeruse_V1_AppInfo()
            info.name = app.name
            info.bundleID = app.bundleID
            info.isRunning = app.isRunning
            info.daysSinceUsed = app.daysSinceUsed
            return info
        }
        return response
    }

    public func getAppState(
        request: Computeruse_V1_GetAppStateRequest,
        context: GRPCCore.ServerContext
    ) async throws -> Computeruse_V1_GetAppStateResponse {
        let app = request.app
        guard !app.isEmpty else {
            throw RPCError(code: .invalidArgument, message: "app is required")
        }
        let pid = try AppDiscovery.shared.resolvePID(app: app)
        let snapshot: AppStateSnapshot
        do {
            snapshot = try await AppSnapshotBuilder.build(pid: pid, app: app)
        } catch ComputerUseError.noWindow {
            // App is running but has no visible window. Re-open it so macOS creates one,
            // wait briefly for it to appear, then retry once.
            fputs("[tingly-cu-native] no window for \(app), reopening to create one\n", stderr)
            try AppDiscovery.shared.reopenToCreateWindow(app: app)
            try await Task.sleep(for: .milliseconds(800))
            do {
                snapshot = try await AppSnapshotBuilder.build(pid: pid, app: app)
            } catch {
                fputs("[tingly-cu-native] getAppState error after reopen: \(error)\n", stderr)
                throw RPCError(code: .internalError, message: "getAppState failed: \(error)")
            }
        } catch {
            fputs("[tingly-cu-native] getAppState error: \(error)\n", stderr)
            throw RPCError(code: .internalError, message: "getAppState failed: \(error)")
        }
        snapshotCache.set(snapshot, app: app)

        var response = Computeruse_V1_GetAppStateResponse()
        response.accessibilityTree = snapshot.accessibilityTree
        response.screenshotPng = snapshot.screenshotPNG
        var appInfo = Computeruse_V1_AppInfo()
        appInfo.name = snapshot.appName
        appInfo.isRunning = true
        response.appInfo = appInfo
        var bounds = Computeruse_V1_Rect()
        bounds.x = Double(snapshot.windowBounds.origin.x)
        bounds.y = Double(snapshot.windowBounds.origin.y)
        bounds.width = Double(snapshot.windowBounds.width)
        bounds.height = Double(snapshot.windowBounds.height)
        response.windowBounds = bounds
        return response
    }

    // MARK: - Action tools

    public func click(
        request: Computeruse_V1_ClickRequest,
        context: GRPCCore.ServerContext
    ) async throws -> Computeruse_V1_ActionResponse {
        return await actionResult {
            let pid = try AppDiscovery.shared.resolvePID(app: request.app)
            let snapshot = snapshotCache.get(app: request.app)
            let elementIndex = request.elementIndex.isEmpty ? nil : request.elementIndex
            let x = request.x == 0 && request.y == 0 ? nil : Optional(request.x)
            let y = request.x == 0 && request.y == 0 ? nil : Optional(request.y)
            try await InputSimulator.click(
                pid: pid,
                elementIndex: elementIndex,
                x: x, y: y,
                snapshot: snapshot,
                clickCount: max(1, Int(request.clickCount)),
                button: mouseButtonKind(from: request.mouseButton)
            )
        }
    }

    public func typeText(
        request: Computeruse_V1_TypeTextRequest,
        context: GRPCCore.ServerContext
    ) async throws -> Computeruse_V1_ActionResponse {
        return await actionResult {
            let pid = try AppDiscovery.shared.resolvePID(app: request.app)
            try await InputSimulator.typeText(pid: pid, text: request.text)
        }
    }

    public func pressKey(
        request: Computeruse_V1_PressKeyRequest,
        context: GRPCCore.ServerContext
    ) async throws -> Computeruse_V1_ActionResponse {
        return await actionResult {
            let pid = try AppDiscovery.shared.resolvePID(app: request.app)
            try await InputSimulator.pressKey(pid: pid, key: request.key)
        }
    }

    public func scroll(
        request: Computeruse_V1_ScrollRequest,
        context: GRPCCore.ServerContext
    ) async throws -> Computeruse_V1_ActionResponse {
        return await actionResult {
            let pid = try AppDiscovery.shared.resolvePID(app: request.app)
            let snapshot = snapshotCache.get(app: request.app)
            try await InputSimulator.scroll(
                pid: pid,
                elementIndex: request.elementIndex,
                snapshot: snapshot,
                direction: scrollDirectionKind(from: request.direction),
                pages: request.pages > 0 ? request.pages : 1.0
            )
        }
    }

    public func drag(
        request: Computeruse_V1_DragRequest,
        context: GRPCCore.ServerContext
    ) async throws -> Computeruse_V1_ActionResponse {
        return await actionResult {
            let pid = try AppDiscovery.shared.resolvePID(app: request.app)
            let snapshot = snapshotCache.get(app: request.app)
            try await InputSimulator.drag(
                pid: pid,
                fromX: request.fromX, fromY: request.fromY,
                toX: request.toX, toY: request.toY,
                snapshot: snapshot
            )
        }
    }

    public func performSecondaryAction(
        request: Computeruse_V1_PerformSecondaryActionRequest,
        context: GRPCCore.ServerContext
    ) async throws -> Computeruse_V1_ActionResponse {
        return await actionResult {
            let pid = try AppDiscovery.shared.resolvePID(app: request.app)
            let snapshot = snapshotCache.get(app: request.app)
            try await InputSimulator.performSecondaryAction(
                pid: pid,
                elementIndex: request.elementIndex,
                action: request.action,
                snapshot: snapshot
            )
        }
    }

    public func setValue(
        request: Computeruse_V1_SetValueRequest,
        context: GRPCCore.ServerContext
    ) async throws -> Computeruse_V1_ActionResponse {
        return await actionResult {
            let pid = try AppDiscovery.shared.resolvePID(app: request.app)
            let snapshot = snapshotCache.get(app: request.app)
            try await InputSimulator.setValue(
                pid: pid,
                elementIndex: request.elementIndex,
                value: request.value,
                snapshot: snapshot
            )
        }
    }

    // MARK: - Lifecycle

    public func turnEnded(
        request: Computeruse_V1_TurnEndedRequest,
        context: GRPCCore.ServerContext
    ) async throws -> Computeruse_V1_TurnEndedResponse {
        SoftwareCursorOverlay.shared.hide()
        snapshotCache.clear()
        return Computeruse_V1_TurnEndedResponse()
    }

    // MARK: - Permissions

    public func checkPermissions(
        request: Computeruse_V1_CheckPermissionsRequest,
        context: GRPCCore.ServerContext
    ) async throws -> Computeruse_V1_CheckPermissionsResponse {
        let result = PermissionChecker().check()
        var response = Computeruse_V1_CheckPermissionsResponse()
        response.accessibilityGranted = result.accessibilityGranted
        response.screenRecordingGranted = result.screenRecordingGranted
        response.accessibilitySettingsURL = result.accessibilitySettingsURL
        response.screenRecordingSettingsURL = result.screenRecordingSettingsURL
        return response
    }

    // MARK: - Helpers

    private func actionResult(_ body: () async throws -> Void) async -> Computeruse_V1_ActionResponse {
        var response = Computeruse_V1_ActionResponse()
        do {
            try await body()
            response.success = true
        } catch {
            response.success = false
            response.error = error.localizedDescription
        }
        return response
    }

    private func mouseButtonKind(from pb: Computeruse_V1_MouseButton) -> MouseButtonKind {
        switch pb {
        case .right:  return .right
        case .middle: return .middle
        default:      return .left
        }
    }

    private func scrollDirectionKind(from pb: Computeruse_V1_ScrollDirection) -> ScrollDirectionKind {
        switch pb {
        case .up:    return .up
        case .down:  return .down
        case .left:  return .left
        case .right: return .right
        default:     return .down
        }
    }
}
