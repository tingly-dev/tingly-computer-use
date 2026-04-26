package tools

import (
	"context"
	"fmt"
	"math"

	"github.com/mark3labs/mcp-go/mcp"
	pb "github.com/tingly-dev/tingly-computer-use/pkg/proto/computeruse/v1"
)

func (h *Handlers) Click(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	args, _ := req.Params.Arguments.(map[string]any)
	app, _ := args["app"].(string)
	if app == "" {
		return mcp.NewToolResultError("missing required parameter: app"), nil
	}

	// NaN encodes "coordinate not provided" so that legitimate (0,0) clicks
	// are not mistaken for the sentinel. The Swift side checks isNaN.
	pbReq := &pb.ClickRequest{App: app, X: math.NaN(), Y: math.NaN()}

	if v, ok := args["element_index"].(string); ok && v != "" {
		pbReq.ElementIndex = v
	}
	if v, ok := args["x"].(float64); ok {
		pbReq.X = v
	}
	if v, ok := args["y"].(float64); ok {
		pbReq.Y = v
	}
	if v, ok := args["click_count"].(float64); ok && v >= 1 {
		pbReq.ClickCount = int32(v)
	}
	switch args["mouse_button"] {
	case "right":
		pbReq.MouseButton = pb.MouseButton_MOUSE_BUTTON_RIGHT
	case "middle":
		pbReq.MouseButton = pb.MouseButton_MOUSE_BUTTON_MIDDLE
	default:
		pbReq.MouseButton = pb.MouseButton_MOUSE_BUTTON_LEFT
	}

	if err := h.client.Click(ctx, pbReq); err != nil {
		return mcp.NewToolResultError(err.Error()), nil
	}
	return mcp.NewToolResultText("clicked"), nil
}

func (h *Handlers) TypeText(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	args, _ := req.Params.Arguments.(map[string]any)
	app, _ := args["app"].(string)
	text, _ := args["text"].(string)
	if app == "" || text == "" {
		return mcp.NewToolResultError("missing required parameters: app, text"), nil
	}
	if err := h.client.TypeText(ctx, app, text); err != nil {
		return mcp.NewToolResultError(err.Error()), nil
	}
	return mcp.NewToolResultText(fmt.Sprintf("typed %d characters", len([]rune(text)))), nil
}

func (h *Handlers) PressKey(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	args, _ := req.Params.Arguments.(map[string]any)
	app, _ := args["app"].(string)
	key, _ := args["key"].(string)
	if app == "" || key == "" {
		return mcp.NewToolResultError("missing required parameters: app, key"), nil
	}
	if err := h.client.PressKey(ctx, app, key); err != nil {
		return mcp.NewToolResultError(err.Error()), nil
	}
	return mcp.NewToolResultText(fmt.Sprintf("pressed %q", key)), nil
}

func (h *Handlers) Scroll(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	args, _ := req.Params.Arguments.(map[string]any)
	app, _ := args["app"].(string)
	elementIndex, _ := args["element_index"].(string)
	dirStr, _ := args["direction"].(string)
	if app == "" || elementIndex == "" || dirStr == "" {
		return mcp.NewToolResultError("missing required parameters: app, element_index, direction"), nil
	}

	pages := 1.0
	if v, ok := args["pages"].(float64); ok && v > 0 {
		pages = v
	}

	var dir pb.ScrollDirection
	switch dirStr {
	case "up":
		dir = pb.ScrollDirection_SCROLL_DIRECTION_UP
	case "down":
		dir = pb.ScrollDirection_SCROLL_DIRECTION_DOWN
	case "left":
		dir = pb.ScrollDirection_SCROLL_DIRECTION_LEFT
	case "right":
		dir = pb.ScrollDirection_SCROLL_DIRECTION_RIGHT
	default:
		return mcp.NewToolResultError(fmt.Sprintf("invalid direction %q", dirStr)), nil
	}

	if err := h.client.Scroll(ctx, &pb.ScrollRequest{
		App:          app,
		ElementIndex: elementIndex,
		Direction:    dir,
		Pages:        pages,
	}); err != nil {
		return mcp.NewToolResultError(err.Error()), nil
	}
	return mcp.NewToolResultText(fmt.Sprintf("scrolled %s %.1f page(s)", dirStr, pages)), nil
}

func (h *Handlers) Drag(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	args, _ := req.Params.Arguments.(map[string]any)
	app, _ := args["app"].(string)
	fromX, _ := args["from_x"].(float64)
	fromY, _ := args["from_y"].(float64)
	toX, _ := args["to_x"].(float64)
	toY, _ := args["to_y"].(float64)
	if app == "" {
		return mcp.NewToolResultError("missing required parameter: app"), nil
	}
	if err := h.client.Drag(ctx, &pb.DragRequest{
		App:   app,
		FromX: fromX,
		FromY: fromY,
		ToX:   toX,
		ToY:   toY,
	}); err != nil {
		return mcp.NewToolResultError(err.Error()), nil
	}
	return mcp.NewToolResultText("dragged"), nil
}

func (h *Handlers) PerformSecondaryAction(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	args, _ := req.Params.Arguments.(map[string]any)
	app, _ := args["app"].(string)
	elementIndex, _ := args["element_index"].(string)
	action, _ := args["action"].(string)
	if app == "" || elementIndex == "" || action == "" {
		return mcp.NewToolResultError("missing required parameters: app, element_index, action"), nil
	}
	if err := h.client.PerformSecondaryAction(ctx, app, elementIndex, action); err != nil {
		return mcp.NewToolResultError(err.Error()), nil
	}
	return mcp.NewToolResultText(fmt.Sprintf("performed action %q", action)), nil
}

func (h *Handlers) SetValue(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	args, _ := req.Params.Arguments.(map[string]any)
	app, _ := args["app"].(string)
	elementIndex, _ := args["element_index"].(string)
	value, _ := args["value"].(string)
	if app == "" || elementIndex == "" {
		return mcp.NewToolResultError("missing required parameters: app, element_index"), nil
	}
	if err := h.client.SetValue(ctx, app, elementIndex, value); err != nil {
		return mcp.NewToolResultError(err.Error()), nil
	}
	return mcp.NewToolResultText("value set"), nil
}
