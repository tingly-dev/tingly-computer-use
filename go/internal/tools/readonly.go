package tools

import (
	"context"
	"fmt"
	"strings"

	"github.com/mark3labs/mcp-go/mcp"
)

func (h *Handlers) ListApps(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	apps, err := h.client.ListApps(ctx)
	if err != nil {
		return mcp.NewToolResultError(err.Error()), nil
	}

	var sb strings.Builder
	for _, app := range apps {
		status := "recently used"
		if app.IsRunning {
			status = "running"
		}
		fmt.Fprintf(&sb, "%s (%s) — %s\n", app.Name, app.BundleID, status)
	}
	return mcp.NewToolResultText(sb.String()), nil
}

func (h *Handlers) GetAppState(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	args, _ := req.Params.Arguments.(map[string]any)
	app, _ := args["app"].(string)
	if app == "" {
		return mcp.NewToolResultError("missing required parameter: app"), nil
	}

	result, err := h.client.GetAppState(ctx, app)
	if err != nil {
		return mcp.NewToolResultError(err.Error()), nil
	}

	contents := []mcp.Content{
		mcp.NewTextContent(result.AccessibilityTree),
	}
	if len(result.ScreenshotPNG) > 0 {
		contents = append(contents, mcp.NewImageContent(result.ScreenshotB64, "image/png"))
	}
	return &mcp.CallToolResult{Content: contents}, nil
}
