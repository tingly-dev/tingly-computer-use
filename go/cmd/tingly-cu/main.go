package main

import (
	"context"
	"fmt"
	"os"

	"github.com/tingly-dev/tingly-computer-use/go/internal/bridge"
	"github.com/tingly-dev/tingly-computer-use/go/internal/mcpserver"
)

const version = "0.1.0"

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	cmd := "mcp"
	if len(args) > 0 {
		cmd = args[0]
	}

	switch cmd {
	case "mcp":
		return runMCP()
	case "doctor":
		return runDoctor()
	case "ls-apps":
		return runListApps()
	case "ax":
		if len(args) < 2 {
			return fmt.Errorf("usage: ax <app-name>")
		}
		return runAX(args[1])
	case "snap":
		if len(args) < 2 {
			return fmt.Errorf("usage: snap <app-name> [output.png]")
		}
		out := "snap.png"
		if len(args) >= 3 {
			out = args[2]
		}
		return runSnap(args[1], out)
	case "version":
		fmt.Println(version)
		return nil
	default:
		return fmt.Errorf("unknown command %q; available: mcp, doctor, ls-apps, ax, snap, version", cmd)
	}
}

// withBridge starts the bridge, calls f, then closes.
func withBridge(f func(ctx context.Context, c *bridge.Client) error) error {
	ctx := context.Background()
	mgr, err := bridge.NewManager(bridge.DefaultConfig())
	if err != nil {
		return fmt.Errorf("init bridge: %w", err)
	}
	defer mgr.Close()
	if err := mgr.EnsureRunning(ctx); err != nil {
		return fmt.Errorf("start native bridge: %w", err)
	}
	return f(ctx, mgr.Client())
}

func runMCP() error {
	ctx := context.Background()
	mgr, err := bridge.NewManager(bridge.DefaultConfig())
	if err != nil {
		return fmt.Errorf("init bridge: %w", err)
	}
	defer mgr.Close()
	if err := mgr.EnsureRunning(ctx); err != nil {
		return fmt.Errorf("start native bridge: %w", err)
	}
	srv := mcpserver.New(mgr, version)
	return srv.ServeStdio()
}

func runDoctor() error {
	ctx := context.Background()
	mgr, err := bridge.NewManager(bridge.DefaultConfig())
	if err != nil {
		return fmt.Errorf("init bridge: %w", err)
	}
	defer mgr.Close()
	if err := mgr.EnsureRunning(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "native bridge not available: %v\n", err)
		fmt.Println("FAIL: cannot connect to tingly-cu-native")
		return nil
	}
	client := mgr.Client()
	resp, err := client.CheckPermissions(ctx)
	if err != nil {
		fmt.Fprintf(os.Stderr, "check permissions: %v\n", err)
		return nil
	}
	ok := true
	if !resp.AccessibilityGranted {
		ok = false
		fmt.Printf("FAIL: Accessibility permission not granted\n      Open: %s\n", resp.AccessibilitySettingsUrl)
	} else {
		fmt.Println("OK:   Accessibility")
	}
	if !resp.ScreenRecordingGranted {
		ok = false
		fmt.Printf("FAIL: Screen Recording permission not granted\n      Open: %s\n", resp.ScreenRecordingSettingsUrl)
	} else {
		fmt.Println("OK:   Screen Recording")
	}
	if ok {
		fmt.Println("\nAll permissions granted. tingly-computer-use is ready.")
	}
	return nil
}

func runListApps() error {
	return withBridge(func(ctx context.Context, c *bridge.Client) error {
		apps, err := c.ListApps(ctx)
		if err != nil {
			return err
		}
		fmt.Printf("%-40s  %s\n", "NAME", "BUNDLE ID")
		fmt.Printf("%-40s  %s\n", "----", "---------")
		for _, a := range apps {
			fmt.Printf("%-40s  %s\n", a.Name, a.BundleID)
		}
		fmt.Printf("\n%d apps running\n", len(apps))
		return nil
	})
}

func runAX(app string) error {
	return withBridge(func(ctx context.Context, c *bridge.Client) error {
		state, err := c.GetAppState(ctx, app)
		if err != nil {
			return err
		}
		fmt.Println(state.AccessibilityTree)
		return nil
	})
}

func runSnap(app, outPath string) error {
	return withBridge(func(ctx context.Context, c *bridge.Client) error {
		state, err := c.GetAppState(ctx, app)
		if err != nil {
			return err
		}
		if len(state.ScreenshotPNG) == 0 {
			return fmt.Errorf("no screenshot returned")
		}
		if err := os.WriteFile(outPath, state.ScreenshotPNG, 0644); err != nil {
			return fmt.Errorf("write %s: %w", outPath, err)
		}
		fmt.Printf("saved %d bytes → %s\n", len(state.ScreenshotPNG), outPath)
		return nil
	})
}
