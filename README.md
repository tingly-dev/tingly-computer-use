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

The Go CLI registers eleven MCP tools:

| Tool                       | Purpose                                                          |
|---------------------------|------------------------------------------------------------------|
| `list_apps`               | List running + recently used apps (last 14 days, deny-listed apps filtered) |
| `get_app_state`           | Focus the app's key window, return PNG screenshot + accessibility tree (must be called once per turn) |
| `snapshot`                | **Read-only** PNG + AX tree of an already-running app — never launches, activates, or reopens; fails if the app is not running |
| `click`                   | Click by `element_index` from the AX tree, or by screenshot pixel coords |
| `type_text`               | Type literal Unicode text (per-grapheme keyDown/keyUp pairs)     |
| `press_key`               | Press a key combo in xdotool syntax (`Return`, `super+c`, …)     |
| `scroll`                  | Scroll an element by direction + fractional pages                |
| `drag`                    | Drag from/to screenshot pixel coords                             |
| `perform_secondary_action`| Invoke a non-default AX action (e.g. `AXShowMenu`)               |
| `set_value`               | Set the value of a settable AX element                           |
| `turn_ended`              | Clear per-turn snapshot cache (host signals end of agent turn)   |

### Why no `open_app` / dedicated `close_app` tools?

These actions are deliberately collapsed into the existing surface rather than exposed as separate tools:

- **Open / launch** is folded into `get_app_state`: passing an `app` that is not running causes the native side to launch and activate it, then snapshot — one round-trip instead of two, and no race between launch and capture.
- **Snapshot vs `get_app_state`**: use `snapshot` when you only want to *observe* an app the user already has open (no focus stealing, no launching). Use `get_app_state` when you intend to *act* on the app and need it focused.
- **Close / quit** is intentionally not exposed: terminating other processes is high-risk. The agent can dismiss windows or quit gracefully via `press_key` (`super+w` / `super+q`), which is auditable by the host and still subject to the deny list.


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
# Build Swift native server (debug) + Go CLI in place (for `task mcp` dev loop)
task build

# Release build of both binaries, in place
task build:release

# Release build + copy both binaries side-by-side into ./dist
# (this is what MCP clients should point at — see "MCP client configuration")
task release
```

Build outputs:

- `task build` / `build:release` → `swift/.build/{debug,release}/tingly-cu-native`, `./tingly-cu`
- `task release` → `dist/tingly-cu`, `dist/tingly-cu-native`

The Go binary auto-locates `tingly-cu-native` via, in order:
1. `TINGLY_CU_NATIVE` env var
2. Same directory as the Go binary
3. `$PATH`

`dist/` puts the two binaries in the same directory, so step 2 fires and **no env var is needed** in MCP client configs.

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

`tingly-cu mcp` is a standard **MCP stdio server** (JSON-RPC 2.0 over stdin/stdout). Any MCP-capable host can use it by spawning the binary with `mcp` as its only argument.

**Set up once:**

```bash
task release                # builds release binaries into ./dist
./dist/tingly-cu doctor     # must report OK on Accessibility + Screen Recording
```

`task release` co-locates `tingly-cu` and `tingly-cu-native` under `dist/`, so the Go wrapper auto-discovers the native bridge — **MCP configs only need to point at `dist/tingly-cu`, no `TINGLY_CU_NATIVE` env required**.

Grant the two macOS permissions to **the host process that will spawn `tingly-cu`** (e.g. Claude Desktop.app, your terminal, VS Code), not to `tingly-cu` itself — macOS attributes the access to the parent.

In every example below, replace `/abs/path/to/tingly-computer-use/` with your actual absolute path to the repo.

### Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "tingly-computer-use": {
      "command": "/abs/path/to/tingly-computer-use/dist/tingly-cu",
      "args": ["mcp"]
    }
  }
}
```

Restart Claude Desktop. The tools appear under the 🔨 menu; if not, check `~/Library/Logs/Claude/mcp*.log`.

### Claude Code (CLI)

```bash
claude mcp add tingly-computer-use \
  -- /abs/path/to/tingly-computer-use/dist/tingly-cu mcp

claude mcp list                 # verify it shows up
```

Use `--scope user` to register globally instead of per-project.

### Codex CLI

Add to `~/.codex/config.toml`:

```toml
[mcp_servers.tingly-computer-use]
command = "/abs/path/to/tingly-computer-use/dist/tingly-cu"
args = ["mcp"]
```

### Cursor / Cline / Continue / opencode / Gemini CLI

These hosts all accept the same stdio shape — only the config file path differs:

- Cursor: `~/.cursor/mcp.json` (or project-level `.cursor/mcp.json`)
- Cline (VS Code): `cline_mcp_settings.json` via the Cline panel
- Continue: `~/.continue/config.json` under `experimental.modelContextProtocolServers`
- opencode: `~/.config/opencode/config.json`
- Gemini CLI: `~/.gemini/settings.json` under `mcpServers`

Use the same `command` + `args` pair shown for Claude Desktop above.

### Verify the connection

From any client, calling `list_apps` should return the running app list. If a call hangs or returns "native bridge not available":

1. Re-run `./dist/tingly-cu doctor` — permission revocations are silent.
2. Confirm `dist/tingly-cu-native` exists next to `dist/tingly-cu` (re-run `task release` if not).
3. Tail the host's MCP log, or run the server directly to see structured errors:
   ```bash
   TINGLY_CU_LOG_FORMAT=text TINGLY_CU_LOG_LEVEL=debug ./dist/tingly-cu mcp </dev/null
   ```

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
