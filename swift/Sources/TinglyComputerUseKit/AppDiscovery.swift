import AppKit
import ApplicationServices

/// Discovers running and recently used applications.
public final class AppDiscovery {
    nonisolated(unsafe) public static let shared = AppDiscovery()
    private init() {}

    // MARK: - Safety denylist

    /// Bundle IDs that must never be automated (terminals, password managers, browsers, etc.).
    private static let deniedBundleIDs: Set<String> = [
        // Terminals
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "com.mitchellh.ghostty",
        "com.github.rio-term.rio",
        // Password managers
        "com.1password.1password",
        "com.bitwarden.desktop",
        "com.dashlane.dashlane",
        "com.lastpass.lastpass",
        "com.nordpass.NordPass",
        "me.proton.pass",
        // Browser (can access credentials)
        "com.google.Chrome",
        // Tingly itself / security agents
        "com.apple.SecurityAgent",
        "com.apple.keychainaccess",
    ]

    /// Returns true if the given bundle ID is on the safety denylist.
    public func isDenied(bundleID: String) -> Bool {
        Self.deniedBundleIDs.contains(bundleID)
    }

    // MARK: - List apps

    /// Returns running apps + recently used apps (last 14 days).
    public func listApps() -> [AppInfo] {
        var seen = Set<String>()
        var apps: [AppInfo] = []

        // Running apps via NSWorkspace.
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  let name = app.localizedName else { continue }
            let bid = app.bundleIdentifier ?? ""
            guard !isDenied(bundleID: bid) else { continue }
            let key = bid.isEmpty ? name : bid
            if seen.insert(key).inserted {
                apps.append(AppInfo(name: name, bundleID: bid, isRunning: true, daysSinceUsed: 0))
            }
        }

        // Recently used apps via MDQuery (last 14 days).
        let cutoff = Date().addingTimeInterval(-14 * 24 * 3600)
        if let query = MDQueryCreate(
            nil,
            "kMDItemContentTypeTree == 'com.apple.application-bundle' && kMDItemLastUsedDate >= $time.now(-1209600)" as CFString,
            nil, nil
        ) {
            MDQuerySetMaxCount(query, 200)
            if MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) {
                let count = MDQueryGetResultCount(query)
                for i in 0..<count {
                    guard let rawItem = MDQueryGetResultAtIndex(query, i) else { continue }
                    let mdItem = Unmanaged<MDItem>.fromOpaque(rawItem).takeUnretainedValue()
                    guard let path = MDItemCopyAttribute(mdItem, kMDItemPath) as? String else { continue }
                    if let used = MDItemCopyAttribute(mdItem, kMDItemLastUsedDate) as? Date, used < cutoff { continue }
                    guard let bundle = Bundle(path: path) else { continue }
                    let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                        ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                        ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                    let bid = bundle.bundleIdentifier ?? ""
                    guard !isDenied(bundleID: bid) else { continue }
                    let key = bid.isEmpty ? name : bid
                    if seen.insert(key).inserted {
                        var days: Int32 = 0
                        if let used = MDItemCopyAttribute(mdItem, kMDItemLastUsedDate) as? Date {
                            days = Int32(max(0, Date().timeIntervalSince(used) / 86400))
                        }
                        apps.append(AppInfo(name: name, bundleID: bid, isRunning: false, daysSinceUsed: days))
                    }
                }
            }
        }

        return apps.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // MARK: - Resolve PID (launch if needed)

    /// Resolves a PID for the given app name or bundle identifier.
    /// If the app is not running, attempts to launch it and waits up to 10 s.
    /// Throws ComputerUseError.appNotFound if the app cannot be found or launched.
    public func resolvePID(app: String) throws -> pid_t {
        // 1. Check already-running apps.
        if let pid = findRunning(app: app) { return pid }

        // 2. Try to launch by bundle ID or name.
        guard let runningApp = try launchApp(query: app) else {
            throw ComputerUseError.appNotFound(app)
        }
        return runningApp.processIdentifier
    }

    // MARK: - Private

    private func findRunning(app: String) -> pid_t? {
        for running in NSWorkspace.shared.runningApplications {
            guard running.activationPolicy == .regular else { continue }
            let bid = running.bundleIdentifier ?? ""
            if isDenied(bundleID: bid) { continue }
            let nameMatch   = running.localizedName?.lowercased() == app.lowercased()
            let bundleMatch = bid.lowercased() == app.lowercased()
            if nameMatch || bundleMatch {
                return running.processIdentifier
            }
        }
        return nil
    }

    private func launchApp(query: String) throws -> NSRunningApplication? {
        // Try to find a bundle on disk by bundle ID first, then by name.
        let workspace = NSWorkspace.shared

        // By bundle ID.
        if let url = workspace.urlForApplication(withBundleIdentifier: query) {
            let bid = Bundle(url: url)?.bundleIdentifier ?? ""
            if isDenied(bundleID: bid) {
                throw ComputerUseError.appNotFound("\(query) (blocked by safety policy)")
            }
            return try launchAndWait(url: url)
        }

        // By name via MDQuery.
        guard let mdq = MDQueryCreate(nil,
            "kMDItemContentTypeTree == 'com.apple.application-bundle' && kMDItemFSName == '\(query).app'" as CFString,
            nil, nil) else { return nil }
        MDQuerySetMaxCount(mdq, 5)
        guard MDQueryExecute(mdq, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return nil }
        for i in 0..<MDQueryGetResultCount(mdq) {
            guard let rawItem = MDQueryGetResultAtIndex(mdq, i) else { continue }
            let mdItem = Unmanaged<MDItem>.fromOpaque(rawItem).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(mdItem, kMDItemPath) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            let bid = Bundle(url: url)?.bundleIdentifier ?? ""
            if isDenied(bundleID: bid) {
                throw ComputerUseError.appNotFound("\(query) (blocked by safety policy)")
            }
            return try launchAndWait(url: url)
        }

        return nil
    }

    private func launchAndWait(url: URL) throws -> NSRunningApplication? {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        var launched: NSRunningApplication?
        var launchError: Error?
        let sema = DispatchSemaphore(value: 0)

        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, err in
            launched = app
            launchError = err
            sema.signal()
        }
        sema.wait()

        if let err = launchError { throw err }
        guard let app = launched else { return nil }

        // Wait up to 10 s for the app to become active/ready.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if !app.isTerminated { return app }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return app
    }
}

public struct AppInfo {
    public let name: String
    public let bundleID: String
    public let isRunning: Bool
    public let daysSinceUsed: Int32
}
