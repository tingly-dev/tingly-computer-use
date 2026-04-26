# tingly-computer-use

A macOS computer-use toolkit for AI agents. Exposes screen capture, accessibility-tree introspection, and input simulation as MCP tools, backed by a Swift native gRPC server.

```
┌─────────────────┐   stdio MCP   ┌──────────────┐   gRPC/UDS   ┌─────────────────────┐
│  AI agent host  │ ────────────► │  tingly-cu   │ ───────────► │  tingly-cu-native   │
│ (Claude/Codex…) │               │   (Go CLI)   │              │  (Swift, AppKit)    │
└─────────────────┘               └──────────────┘              └─────────────────────┘
                                                                         │
                                                                         ▼
                                                         macOS Accessibility · ScreenCaptureKit · CGEvent
```

## What it can do

The Go CLI registers ten MCP tools:

| Tool                       | Purpose                                                          |
|---------------------------|------------------------------------------------------------------|
| `list_apps`               | List running + recently used apps (last 14 days, deny-listed apps filtered) |
| `get_app_state`           | Focus the app's key window, return PNG screenshot + accessibility tree (must be called once per turn) |
| `click`                   | Click by `element_index` from the AX tree, or by screenshot pixel coords |
| `type_text`               | Type literal Unicode text (per-grapheme keyDown/keyUp pairs)     |
| `press_key`               | Press a key combo in xdotool syntax (`Return`, `super+c`, …)     |
| `scroll`                  | Scroll an element by direction + fractional pages                |
| `drag`                    | Drag from/to screenshot pixel coords                             |
| `perform_secondary_action`| Invoke a non-default AX action (e.g. `AXShowMenu`)               |
| `set_value`               | Set the value of a settable AX element                           |
| `turn_ended`              | Clear per-turn snapshot cache (host signals end of agent turn)   |

## Requirements

- macOS **15+** (gRPC-Swift v2 generated code requires macOS 15)
- Xcode / Swift toolchain 6.0+
- Go 1.23+
- Permissions, granted to the binary that hosts the agent (the MCP client process):
  - **Accessibility** — System Settings → Privacy & Security → Accessibility
  - **Screen Recording** — System Settings → Privacy & Security → Screen Recording

Run `task doctor` to check both at once.

## Build

```bash
# Build Swift native server (debug) + Go CLI
task build

# Release build
task build:release

# Or directly:
cd swift && swift build --product tingly-cu-native -c release
cd go    && GOWORK=off go build -o tingly-cu ./cmd/tingly-cu
```

Build outputs:

- `swift/.build/{debug,release}/tingly-cu-native`
- `go/tingly-cu`

The Go binary auto-locates `tingly-cu-native` via, in order:
1. `TINGLY_CU_NATIVE` env var
2. Same directory as the Go binary
3. `$PATH`

## Run

```bash
# Start the MCP stdio server (auto-spawns the Swift native process)
task mcp                   # or:  go/tingly-cu mcp

# Diagnostic / utility commands
task doctor                # Check macOS permissions
task list-app              # List running apps
task ax     -- Safari      # Dump accessibility tree of an app
task snap   -- Safari      # Save screenshot to ./snap.png
```

## MCP client configuration

### Claude Desktop / Claude Code

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "tingly-computer-use": {
      "command": "/absolute/path/to/tingly-computer-use/go/tingly-cu",
      "args": ["mcp"],
      "env": {
        "TINGLY_CU_NATIVE": "/absolute/path/to/tingly-computer-use/swift/.build/release/tingly-cu-native"
      }
    }
  }
}
```

### Codex / opencode / Gemini CLI

Any MCP client that speaks stdio works the same way: invoke `tingly-cu mcp`, passing the `TINGLY_CU_NATIVE` env if the native binary isn't on `$PATH` next to the Go binary.

## Configuration (env vars)

| Variable                                | Purpose                                                                                          | Default               |
|-----------------------------------------|--------------------------------------------------------------------------------------------------|-----------------------|
| `TINGLY_CU_NATIVE`                      | Absolute path to `tingly-cu-native`                                                              | (resolves automatically) |
| `TINGLY_CU_LOG_LEVEL`                   | Log threshold: `debug` \| `info` \| `warn` \| `error`                                            | `info`                |
| `TINGLY_CU_LOG_FORMAT`                  | `json` (one JSON object per line) or `text`                                                      | `json`                |
| `TINGLY_CU_DENYLIST`                    | Extra bundle IDs (comma-separated) to add to the deny list                                       | (empty)               |
| `TINGLY_CU_DENYLIST_FILE`               | Path to a file containing one bundle ID per line (`#` starts a comment)                          | (unset)               |
| `TINGLY_CU_ALLOWLIST`                   | Bundle IDs (comma-separated) that bypass all deny rules                                          | (empty)               |
| `TINGLY_CU_ALLOWLIST_ONLY`              | If `1`/`true`, run in **whitelist mode** — only allowlisted apps are permitted                   | `false`               |
| `TINGLY_CU_DISABLE_DEFAULT_DENYLIST`    | If `1`/`true`, drop the built-in baseline (use only your custom list)                            | `false`               |

**Built-in deny baseline** (terminals, password managers, system security agents, Chrome) lives in [`DenyList.defaultDeniedBundleIDs`](swift/Sources/TinglyComputerUseKit/DenyList.swift). Add your own via `TINGLY_CU_DENYLIST_FILE`:

```text
# ~/.config/tingly/denylist.txt
com.apple.Safari       # don't let agents drive my browser
com.tinyspeck.slackmacgap
```

```bash
export TINGLY_CU_DENYLIST_FILE=~/.config/tingly/denylist.txt
```

## Logging

Both Go and Swift sides emit JSON-line logs to stderr:

```json
{"ts":"2026-04-26T10:11:22.345Z","level":"info","msg":"native server listening","socket":"/tmp/tingly-cu-501.sock"}
{"ts":"2026-04-26T10:11:23.012Z","level":"warn","msg":"no window for app, reopening","app":"Safari"}
```

For human-readable output during development:

```bash
TINGLY_CU_LOG_FORMAT=text TINGLY_CU_LOG_LEVEL=debug task mcp
```

## Layout

```
proto/computeruse/v1/computeruse.proto   contract shared by Swift + Go
swift/Sources/TinglyComputerUse/         CLI entry (serve | doctor | version)
swift/Sources/TinglyComputerUseKit/      gRPC service, AX traversal, input simulation
go/cmd/tingly-cu/                        CLI entry (mcp | doctor | ls-apps | ax | snap | version)
go/internal/bridge/                      spawns native, gRPC client wrapper
go/internal/mcpserver/                   MCP tool registration
go/internal/tools/                       per-tool argument coercion + dispatch
build/                                   build/gen-proto scripts
Taskfile.yml                             task runner targets
```

## Regenerating proto code

```bash
# Prerequisites:
#   brew install protobuf swift-protobuf
#   go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
#   go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
#   (Swift gRPC v2 plugin from grpc/grpc-swift)

task gen
```

Generated artifacts (`go/pkg/proto/...`, `swift/Sources/TinglyComputerUseKit/Generated/...`) are checked in.

## Status & limitations

- **macOS-only.** Linux/Windows targets are not implemented.
- **No tests** in this branch yet — Swift `Tests/` is empty, no `*_test.go`. Integration tests against a fixture app are planned.
- The screenshot is base64-encoded into the MCP `CallToolResult`; very large Retina screens can stress the agent's token budget. Streaming-via-resource is on the roadmap.
- `tingly-cu-native` runs in the foreground with no auto-restart-on-crash; the Go side cleans up on `SIGINT/SIGTERM` but does not yet supervise the child.

## License

See [LICENSE](LICENSE).
