import Foundation

/// Minimal JSON-line structured logger that writes to stderr.
///
/// Output format (one line per record):
///   {"ts":"2026-04-26T12:34:56.789Z","level":"info","msg":"…","key":"value",…}
///
/// Level filter via env var `TINGLY_CU_LOG_LEVEL` (debug|info|warn|error). Default: info.
/// Plain-text fallback via `TINGLY_CU_LOG_FORMAT=text` for human-readable stderr in dev.
public enum Log {
    public enum Level: Int, Comparable, Sendable {
        case debug = 0, info = 1, warn = 2, error = 3
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

        var name: String {
            switch self {
            case .debug: return "debug"
            case .info:  return "info"
            case .warn:  return "warn"
            case .error: return "error"
            }
        }

        static func parse(_ s: String?) -> Level {
            switch (s ?? "info").lowercased() {
            case "debug": return .debug
            case "warn", "warning": return .warn
            case "error": return .error
            default: return .info
            }
        }
    }

    private enum Format: Sendable { case json, text }

    private static let level: Level = Level.parse(ProcessInfo.processInfo.environment["TINGLY_CU_LOG_LEVEL"])
    private static let format: Format = {
        switch (ProcessInfo.processInfo.environment["TINGLY_CU_LOG_FORMAT"] ?? "json").lowercased() {
        case "text": return .text
        default: return .json
        }
    }()

    private static let lock = NSLock()
    // ISO8601DateFormatter is documented thread-safe for formatting; the lock
    // already serializes our writes, so this static is safe in practice.
    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static func debug(_ msg: String, _ kv: Any...) { emit(.debug, msg, kv) }
    public static func info (_ msg: String, _ kv: Any...) { emit(.info,  msg, kv) }
    public static func warn (_ msg: String, _ kv: Any...) { emit(.warn,  msg, kv) }
    public static func error(_ msg: String, _ kv: Any...) { emit(.error, msg, kv) }

    // MARK: - Internal

    private static func emit(_ lvl: Level, _ msg: String, _ kv: [Any]) {
        guard lvl >= level else { return }
        let ts = isoFormatter.string(from: Date())
        let pairs = pair(kv)
        let line: String
        switch format {
        case .json:
            line = jsonLine(ts: ts, level: lvl, msg: msg, pairs: pairs)
        case .text:
            line = textLine(ts: ts, level: lvl, msg: msg, pairs: pairs)
        }
        lock.lock()
        defer { lock.unlock() }
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    private static func pair(_ kv: [Any]) -> [(String, Any)] {
        var out: [(String, Any)] = []
        var i = 0
        while i < kv.count {
            let key = "\(kv[i])"
            let val: Any = (i + 1 < kv.count) ? kv[i + 1] : ""
            out.append((key, val))
            i += 2
        }
        return out
    }

    private static func jsonLine(ts: String, level: Level, msg: String, pairs: [(String, Any)]) -> String {
        var dict: [String: Any] = [
            "ts": ts,
            "level": level.name,
            "msg": msg,
        ]
        for (k, v) in pairs { dict[k] = jsonSafe(v) }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "{\"level\":\"\(level.name)\",\"msg\":\"\(escape(msg))\"}"
    }

    private static func textLine(ts: String, level: Level, msg: String, pairs: [(String, Any)]) -> String {
        var s = "\(ts) [\(level.name.uppercased())] \(msg)"
        for (k, v) in pairs { s += " \(k)=\(v)" }
        return s
    }

    private static func jsonSafe(_ v: Any) -> Any {
        switch v {
        case let x as String: return x
        case let x as Int:    return x
        case let x as Double: return x.isFinite ? x : "\(x)"
        case let x as Bool:   return x
        default: return "\(v)"
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
