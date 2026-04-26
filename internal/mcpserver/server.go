// Package mcpserver implements the MCP JSON-RPC 2.0 stdio server,
// exposing 9 computer-use tools backed by the Swift native bridge.
package mcpserver

import (
	"context"

	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"
	"github.com/tingly-dev/tingly-computer-use/internal/bridge"
	"github.com/tingly-dev/tingly-computer-use/internal/tools"
)

// Server is the MCP stdio server.
type Server struct {
	mgr     *bridge.Manager
	version string
}

// New creates a Server backed by the given bridge manager.
func New(mgr *bridge.Manager, version string) *Server {
	return &Server{mgr: mgr, version: version}
}

// ServeStdio starts the MCP server on stdin/stdout and blocks until done.
func (s *Server) ServeStdio() error {
	mcpSrv := server.NewMCPServer(
		"tingly-computer-use",
		s.version,
		server.WithToolCapabilities(true),
	)

	client, err := s.mgr.Client()
	if err != nil {
		return err
	}
	h := tools.NewHandlers(client)

	registerTools(mcpSrv, h)

	return server.ServeStdio(mcpSrv)
}

func registerTools(srv *server.MCPServer, h *tools.Handlers) {
	// ── Read-only tools ──────────────────────────────────────────────────────

	srv.AddTool(
		mcp.NewTool("list_apps",
			mcp.WithDescription("List the apps on this computer. Returns running and recently used apps."),
			mcp.WithReadOnlyHintAnnotation(true),
		),
		func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			return h.ListApps(ctx, req)
		},
	)

	srv.AddTool(
		mcp.NewTool("get_app_state",
			mcp.WithDescription("Start an app use session if needed, then get the state of the app's key window and return a screenshot and accessibility tree. This must be called once per assistant turn before interacting with the app."),
			mcp.WithReadOnlyHintAnnotation(true),
			mcp.WithString("app",
				mcp.Required(),
				mcp.Description("App name or bundle identifier"),
			),
		),
		func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			return h.GetAppState(ctx, req)
		},
	)

	// ── Action tools ─────────────────────────────────────────────────────────

	srv.AddTool(
		mcp.NewTool("click",
			mcp.WithDescription("Click an element by index or pixel coordinates from screenshot."),
			mcp.WithString("app",
				mcp.Required(),
				mcp.Description("App name or bundle identifier"),
			),
			mcp.WithString("element_index",
				mcp.Description("Element index from accessibility tree"),
			),
			mcp.WithNumber("x",
				mcp.Description("X coordinate in screenshot pixel coordinates"),
			),
			mcp.WithNumber("y",
				mcp.Description("Y coordinate in screenshot pixel coordinates"),
			),
			mcp.WithNumber("click_count",
				mcp.Description("Number of clicks. Defaults to 1"),
			),
			mcp.WithString("mouse_button",
				mcp.Description("Mouse button: left, right, or middle. Defaults to left"),
				mcp.Enum("left", "right", "middle"),
			),
		),
		func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			return h.Click(ctx, req)
		},
	)

	srv.AddTool(
		mcp.NewTool("type_text",
			mcp.WithDescription("Type literal text using keyboard input."),
			mcp.WithString("app",
				mcp.Required(),
				mcp.Description("App name or bundle identifier"),
			),
			mcp.WithString("text",
				mcp.Required(),
				mcp.Description("Literal text to type"),
			),
		),
		func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			return h.TypeText(ctx, req)
		},
	)

	srv.AddTool(
		mcp.NewTool("press_key",
			mcp.WithDescription("Press a key or key-combination. Supports xdotool key syntax.\nExamples: \"Return\", \"Tab\", \"super+c\", \"F1\", \"BackSpace\", \"KP_0\""),
			mcp.WithString("app",
				mcp.Required(),
				mcp.Description("App name or bundle identifier"),
			),
			mcp.WithString("key",
				mcp.Required(),
				mcp.Description("Key or key combination (xdotool syntax)"),
			),
		),
		func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			return h.PressKey(ctx, req)
		},
	)

	srv.AddTool(
		mcp.NewTool("scroll",
			mcp.WithDescription("Scroll an element in a direction by a number of pages."),
			mcp.WithString("app",
				mcp.Required(),
				mcp.Description("App name or bundle identifier"),
			),
			mcp.WithString("element_index",
				mcp.Required(),
				mcp.Description("Element identifier from accessibility tree"),
			),
			mcp.WithString("direction",
				mcp.Required(),
				mcp.Description("Scroll direction"),
				mcp.Enum("up", "down", "left", "right"),
			),
			mcp.WithNumber("pages",
				mcp.Description("Number of pages to scroll. Fractional values supported. Defaults to 1"),
			),
		),
		func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			return h.Scroll(ctx, req)
		},
	)

	srv.AddTool(
		mcp.NewTool("drag",
			mcp.WithDescription("Drag from one point to another using pixel coordinates."),
			mcp.WithString("app",
				mcp.Required(),
				mcp.Description("App name or bundle identifier"),
			),
			mcp.WithNumber("from_x", mcp.Required(), mcp.Description("Start X coordinate")),
			mcp.WithNumber("from_y", mcp.Required(), mcp.Description("Start Y coordinate")),
			mcp.WithNumber("to_x", mcp.Required(), mcp.Description("End X coordinate")),
			mcp.WithNumber("to_y", mcp.Required(), mcp.Description("End Y coordinate")),
		),
		func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			return h.Drag(ctx, req)
		},
	)

	srv.AddTool(
		mcp.NewTool("perform_secondary_action",
			mcp.WithDescription("Invoke a secondary accessibility action exposed by an element."),
			mcp.WithString("app",
				mcp.Required(),
				mcp.Description("App name or bundle identifier"),
			),
			mcp.WithString("element_index",
				mcp.Required(),
				mcp.Description("Element identifier from accessibility tree"),
			),
			mcp.WithString("action",
				mcp.Required(),
				mcp.Description("Secondary accessibility action name (from get_app_state result)"),
			),
		),
		func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			return h.PerformSecondaryAction(ctx, req)
		},
	)

	srv.AddTool(
		mcp.NewTool("set_value",
			mcp.WithDescription("Set the value of a settable accessibility element."),
			mcp.WithString("app",
				mcp.Required(),
				mcp.Description("App name or bundle identifier"),
			),
			mcp.WithString("element_index",
				mcp.Required(),
				mcp.Description("Element identifier from accessibility tree"),
			),
			mcp.WithString("value",
				mcp.Required(),
				mcp.Description("Value to assign"),
			),
		),
		func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			return h.SetValue(ctx, req)
		},
	)

	// Register turn-ended notification handler (not a tool, but lifecycle hook).
	// Callers can invoke "turn_ended" as a tool for simplicity.
	srv.AddTool(
		mcp.NewTool("turn_ended",
			mcp.WithDescription("Signal end of agent turn. Clears visual cursor overlay state."),
			mcp.WithString("turn_id", mcp.Description("Optional turn identifier")),
			mcp.WithString("thread_id", mcp.Description("Optional thread identifier")),
		),
		func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			return h.TurnEnded(ctx, req)
		},
	)
}
