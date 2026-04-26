package bridge

import (
	"context"
	"encoding/base64"
	"fmt"

	pb "github.com/tingly-dev/tingly-computer-use/go/pkg/proto/computeruse/v1"
)

// Client wraps the generated gRPC stub with ergonomic helpers.
type Client struct {
	stub pb.ComputerUseServiceClient
}

func newClient(stub pb.ComputerUseServiceClient) *Client {
	return &Client{stub: stub}
}

// AppInfo mirrors pb.AppInfo for callers that don't want proto imports.
type AppInfo struct {
	Name         string
	BundleID     string
	IsRunning    bool
	DaysSinceUse int32
}

// AppStateResult holds the result of GetAppState.
type AppStateResult struct {
	AccessibilityTree string
	ScreenshotPNG     []byte // raw PNG bytes
	ScreenshotB64     string // base64-encoded PNG for MCP image content
	AppInfo           AppInfo
}

// PermissionsResult holds the result of CheckPermissions.
type PermissionsResult struct {
	AccessibilityGranted       bool
	ScreenRecordingGranted     bool
	AccessibilitySettingsUrl   string
	ScreenRecordingSettingsUrl string
}

func (c *Client) ListApps(ctx context.Context) ([]AppInfo, error) {
	resp, err := c.stub.ListApps(ctx, &pb.ListAppsRequest{})
	if err != nil {
		return nil, fmt.Errorf("ListApps: %w", err)
	}
	apps := make([]AppInfo, len(resp.Apps))
	for i, a := range resp.Apps {
		apps[i] = AppInfo{
			Name:         a.Name,
			BundleID:     a.BundleId,
			IsRunning:    a.IsRunning,
			DaysSinceUse: a.DaysSinceUsed,
		}
	}
	return apps, nil
}

func (c *Client) GetAppState(ctx context.Context, app string) (*AppStateResult, error) {
	resp, err := c.stub.GetAppState(ctx, &pb.GetAppStateRequest{App: app})
	if err != nil {
		return nil, fmt.Errorf("GetAppState(%q): %w", app, err)
	}
	return &AppStateResult{
		AccessibilityTree: resp.AccessibilityTree,
		ScreenshotPNG:     resp.ScreenshotPng,
		ScreenshotB64:     base64.StdEncoding.EncodeToString(resp.ScreenshotPng),
		AppInfo: AppInfo{
			Name:      resp.AppInfo.GetName(),
			BundleID:  resp.AppInfo.GetBundleId(),
			IsRunning: resp.AppInfo.GetIsRunning(),
		},
	}, nil
}

func (c *Client) Click(ctx context.Context, req *pb.ClickRequest) error {
	resp, err := c.stub.Click(ctx, req)
	if err != nil {
		return fmt.Errorf("Click: %w", err)
	}
	if !resp.Success {
		return fmt.Errorf("Click: %s", resp.Error)
	}
	return nil
}

func (c *Client) TypeText(ctx context.Context, app, text string) error {
	resp, err := c.stub.TypeText(ctx, &pb.TypeTextRequest{App: app, Text: text})
	if err != nil {
		return fmt.Errorf("TypeText: %w", err)
	}
	if !resp.Success {
		return fmt.Errorf("TypeText: %s", resp.Error)
	}
	return nil
}

func (c *Client) PressKey(ctx context.Context, app, key string) error {
	resp, err := c.stub.PressKey(ctx, &pb.PressKeyRequest{App: app, Key: key})
	if err != nil {
		return fmt.Errorf("PressKey: %w", err)
	}
	if !resp.Success {
		return fmt.Errorf("PressKey: %s", resp.Error)
	}
	return nil
}

func (c *Client) Scroll(ctx context.Context, req *pb.ScrollRequest) error {
	resp, err := c.stub.Scroll(ctx, req)
	if err != nil {
		return fmt.Errorf("Scroll: %w", err)
	}
	if !resp.Success {
		return fmt.Errorf("Scroll: %s", resp.Error)
	}
	return nil
}

func (c *Client) Drag(ctx context.Context, req *pb.DragRequest) error {
	resp, err := c.stub.Drag(ctx, req)
	if err != nil {
		return fmt.Errorf("Drag: %w", err)
	}
	if !resp.Success {
		return fmt.Errorf("Drag: %s", resp.Error)
	}
	return nil
}

func (c *Client) PerformSecondaryAction(ctx context.Context, app, elementIndex, action string) error {
	resp, err := c.stub.PerformSecondaryAction(ctx, &pb.PerformSecondaryActionRequest{
		App:          app,
		ElementIndex: elementIndex,
		Action:       action,
	})
	if err != nil {
		return fmt.Errorf("PerformSecondaryAction: %w", err)
	}
	if !resp.Success {
		return fmt.Errorf("PerformSecondaryAction: %s", resp.Error)
	}
	return nil
}

func (c *Client) SetValue(ctx context.Context, app, elementIndex, value string) error {
	resp, err := c.stub.SetValue(ctx, &pb.SetValueRequest{
		App:          app,
		ElementIndex: elementIndex,
		Value:        value,
	})
	if err != nil {
		return fmt.Errorf("SetValue: %w", err)
	}
	if !resp.Success {
		return fmt.Errorf("SetValue: %s", resp.Error)
	}
	return nil
}

func (c *Client) TurnEnded(ctx context.Context, turnID, threadID string) error {
	_, err := c.stub.TurnEnded(ctx, &pb.TurnEndedRequest{TurnId: turnID, ThreadId: threadID})
	return err
}

func (c *Client) CheckPermissions(ctx context.Context) (*PermissionsResult, error) {
	resp, err := c.stub.CheckPermissions(ctx, &pb.CheckPermissionsRequest{})
	if err != nil {
		return nil, fmt.Errorf("CheckPermissions: %w", err)
	}
	return &PermissionsResult{
		AccessibilityGranted:       resp.AccessibilityGranted,
		ScreenRecordingGranted:     resp.ScreenRecordingGranted,
		AccessibilitySettingsUrl:   resp.AccessibilitySettingsUrl,
		ScreenRecordingSettingsUrl: resp.ScreenRecordingSettingsUrl,
	}, nil
}
