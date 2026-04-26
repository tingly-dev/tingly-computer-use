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
	case "version":
		fmt.Println(version)
		return nil
	default:
		return fmt.Errorf("unknown command %q; available: mcp, doctor, version", cmd)
	}
}

func runMCP() error {
	ctx := context.Background()

	// Start or connect to the Swift native bridge process.
	mgr, err := bridge.NewManager(bridge.DefaultConfig())
	if err != nil {
		return fmt.Errorf("init bridge: %w", err)
	}
	defer mgr.Close()

	if err := mgr.EnsureRunning(ctx); err != nil {
		return fmt.Errorf("start native bridge: %w", err)
	}

	// Start MCP stdio server (blocks until stdin is closed).
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
