package tools

import (
	"context"

	"github.com/mark3labs/mcp-go/mcp"
)

func (h *Handlers) TurnEnded(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	args, _ := req.Params.Arguments.(map[string]any)
	turnID, _ := args["turn_id"].(string)
	threadID, _ := args["thread_id"].(string)
	if err := h.client.TurnEnded(ctx, turnID, threadID); err != nil {
		return mcp.NewToolResultError(err.Error()), nil
	}
	return mcp.NewToolResultText("turn ended"), nil
}
