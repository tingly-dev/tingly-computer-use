import Foundation

/// Configurable safety list for app automation.
///
/// Defaults: a baseline of high-risk bundle IDs (terminals, password managers,
/// security agents, browsers that hold credentials).
///
/// Environment overrides (read once at first access):
///   TINGLY_CU_DENYLIST           extra bundle IDs (comma-separated) to deny on top of defaults
///   TINGLY_CU_DENYLIST_FILE      path to a file with one bundle ID per line; '#' starts a comment
///   TINGLY_CU_ALLOWLIST          bundle IDs (comma-separated) that bypass all deny rules
///   TINGLY_CU_ALLOWLIST_ONLY     if "1"/"true", ONLY allowlist entries are permitted (whitelist mode)
///   TINGLY_CU_DISABLE_DEFAULT_DENYLIST   if "1"/"true", drop the built-in baseline (use only custom list)
public final class DenyList: @unchecked Sendable {
    public static let shared = DenyList()

    private let denied: Set<String>
    private let allowed: Set<String>
    private let allowlistOnly: Bool

    /// Built-in baseline of bundle IDs that must never be automated.
    public static let defaultDeniedBundleIDs: Set<String> = [
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
        // Browsers (hold credentials)
        "com.google.Chrome",
        // System security agents
        "com.apple.SecurityAgent",
        "com.apple.keychainaccess",
    ]

    private init() {
        let env = ProcessInfo.processInfo.environment

        var denied: Set<String> = DenyList.boolFlag(env["TINGLY_CU_DISABLE_DEFAULT_DENYLIST"])
            ? []
            : DenyList.defaultDeniedBundleIDs

        denied.formUnion(DenyList.parseList(env["TINGLY_CU_DENYLIST"]))
        if let file = env["TINGLY_CU_DENYLIST_FILE"] {
            denied.formUnion(DenyList.readListFile(file))
        }

        let allowed = DenyList.parseList(env["TINGLY_CU_ALLOWLIST"])
        let allowlistOnly = DenyList.boolFlag(env["TINGLY_CU_ALLOWLIST_ONLY"])

        self.denied = denied
        self.allowed = allowed
        self.allowlistOnly = allowlistOnly
    }

    /// Returns true if `bundleID` is blocked by safety policy.
    public func isDenied(bundleID: String) -> Bool {
        if allowed.contains(bundleID) {
            return false
        }
        if allowlistOnly {
            // Whitelist mode: anything not in the allowlist is denied.
            return true
        }
        return denied.contains(bundleID)
    }

    // MARK: - Parsing helpers

    private static func parseList(_ value: String?) -> Set<String> {
        guard let v = value else { return [] }
        return Set(
            v.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private static func readListFile(_ path: String) -> Set<String> {
        guard let data = try? String(contentsOfFile: path, encoding: .utf8) else {
            Log.warn("denylist file not readable", "path", path)
            return []
        }
        var out: Set<String> = []
        for raw in data.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            // Allow inline "# comment" trailing.
            let bid = line.split(separator: "#", maxSplits: 1).first
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? line
            if !bid.isEmpty { out.insert(bid) }
        }
        return out
    }

    private static func boolFlag(_ value: String?) -> Bool {
        guard let v = value?.lowercased() else { return false }
        return v == "1" || v == "true" || v == "yes"
    }
}
