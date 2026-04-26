// Package obs provides shared observability helpers — currently a configurable
// log/slog logger that mirrors the Swift side's structured-log conventions.
//
// Configuration via environment variables (read once at init):
//
//	TINGLY_CU_LOG_LEVEL    debug | info | warn | error  (default: info)
//	TINGLY_CU_LOG_FORMAT   json | text                  (default: json)
//
// Output is always written to stderr; stdout is reserved for MCP JSON-RPC
// traffic and CLI output.
package obs

import (
	"log/slog"
	"os"
	"strings"
)

// Logger is the package-level structured logger. Use the helpers below or
// access this directly for advanced cases.
var Logger *slog.Logger

func init() {
	level := parseLevel(os.Getenv("TINGLY_CU_LOG_LEVEL"))
	opts := &slog.HandlerOptions{Level: level}

	var handler slog.Handler
	switch strings.ToLower(os.Getenv("TINGLY_CU_LOG_FORMAT")) {
	case "text":
		handler = slog.NewTextHandler(os.Stderr, opts)
	default:
		handler = slog.NewJSONHandler(os.Stderr, opts)
	}
	Logger = slog.New(handler)
}

func parseLevel(s string) slog.Level {
	switch strings.ToLower(s) {
	case "debug":
		return slog.LevelDebug
	case "warn", "warning":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}

// Debug logs at debug level with key/value pairs.
func Debug(msg string, kv ...any) { Logger.Debug(msg, kv...) }

// Info logs at info level with key/value pairs.
func Info(msg string, kv ...any) { Logger.Info(msg, kv...) }

// Warn logs at warn level with key/value pairs.
func Warn(msg string, kv ...any) { Logger.Warn(msg, kv...) }

// Error logs at error level with key/value pairs.
func Error(msg string, kv ...any) { Logger.Error(msg, kv...) }
