// Package bridge manages the lifecycle of the Swift native process and
// provides a gRPC client for communicating with it.
package bridge

import (
	"context"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/connectivity"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/keepalive"

	"github.com/tingly-dev/tingly-computer-use/internal/obs"
	pb "github.com/tingly-dev/tingly-computer-use/pkg/proto/computeruse/v1"
)

const (
	defaultStartTimeout = 10 * time.Second
)

// Config holds bridge configuration.
type Config struct {
	// Path to the tingly-cu-native binary.
	// Resolved automatically from alongside this binary or PATH.
	NativeBinPath string

	// Unix socket path. Defaults to /tmp/tingly-cu-<uid>.sock
	SocketPath string
}

// DefaultConfig returns a Config with sensible defaults.
func DefaultConfig() Config {
	return Config{
		SocketPath: fmt.Sprintf("/tmp/tingly-cu-%d.sock", os.Getuid()),
	}
}

// Manager manages the Swift native process and its gRPC connection.
type Manager struct {
	cfg    Config
	mu     sync.Mutex
	cmd    *exec.Cmd
	conn   *grpc.ClientConn
	client *Client
}

// NewManager creates a Manager with the given config.
func NewManager(cfg Config) (*Manager, error) {
	if cfg.NativeBinPath == "" {
		bin, err := resolveNativeBin()
		if err != nil {
			return nil, err
		}
		cfg.NativeBinPath = bin
	}
	return &Manager{cfg: cfg}, nil
}

// EnsureRunning starts the native process if not already running and
// establishes a gRPC connection.
func (m *Manager) EnsureRunning(ctx context.Context) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Check if existing connection is still healthy.
	if m.conn != nil {
		state := m.conn.GetState()
		if state != connectivity.Shutdown && state != connectivity.TransientFailure {
			return nil
		}
		_ = m.conn.Close()
		m.conn = nil
		m.client = nil
	}

	// Start native process if socket doesn't exist or is stale (not connectable).
	if !socketConnectable(m.cfg.SocketPath) {
		// Remove stale socket file if present.
		_ = os.Remove(m.cfg.SocketPath)
		if err := m.startNative(); err != nil {
			return fmt.Errorf("start native process: %w", err)
		}
	}

	// Wait for socket to appear and be connectable.
	dialCtx, cancel := context.WithTimeout(ctx, defaultStartTimeout)
	defer cancel()
	if err := waitForSocket(dialCtx, m.cfg.SocketPath); err != nil {
		return fmt.Errorf("wait for native socket: %w", err)
	}

	conn, err := grpc.NewClient(
		"unix://"+m.cfg.SocketPath,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		// Local Unix socket — disable keepalive pings and BDP estimation pings to
		// avoid ENHANCE_YOUR_CALM / GOAWAY errors from the Swift gRPC-NIO server.
		// Setting InitialConnWindowSize >= defaultWindowSize disables the dynamic
		// window / BDP estimator which sends unsolicited PING frames.
		grpc.WithInitialConnWindowSize(1<<20), // 1 MiB — disables BDP ping
		grpc.WithKeepaliveParams(keepalive.ClientParameters{
			Time:                time.Duration(1<<63 - 1), // effectively disabled
			PermitWithoutStream: false,
		}),
	)
	if err != nil {
		return fmt.Errorf("dial native socket: %w", err)
	}

	m.conn = conn
	m.client = newClient(pb.NewComputerUseServiceClient(conn))
	return nil
}

// Client returns the gRPC client wrapper. Returns an error if EnsureRunning
// has not been called or the connection has been closed.
func (m *Manager) Client() (*Client, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.client == nil {
		return nil, fmt.Errorf("bridge.Manager: Client() called before EnsureRunning()")
	}
	return m.client, nil
}

// Close shuts down the gRPC connection and terminates the native process.
func (m *Manager) Close() {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.conn != nil {
		_ = m.conn.Close()
		m.conn = nil
		m.client = nil
	}
	if m.cmd != nil && m.cmd.Process != nil {
		pid := m.cmd.Process.Pid
		_ = m.cmd.Process.Kill()
		_ = m.cmd.Wait()
		m.cmd = nil
		obs.Info("native server stopped", "pid", pid)
	}
}

func (m *Manager) startNative() error {
	cmd := exec.Command(m.cfg.NativeBinPath, "serve", "--socket", m.cfg.SocketPath)
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		return err
	}
	m.cmd = cmd
	obs.Info("spawned native server", "pid", cmd.Process.Pid, "bin", m.cfg.NativeBinPath, "socket", m.cfg.SocketPath)
	return nil
}

func socketConnectable(path string) bool {
	conn, err := net.DialTimeout("unix", path, 300*time.Millisecond)
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}

func waitForSocket(ctx context.Context, path string) error {
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return fmt.Errorf("timeout waiting for socket %s: %w", path, ctx.Err())
		case <-ticker.C:
			if _, err := os.Stat(path); err == nil {
				// Socket file exists — give the server a moment to be fully ready.
				time.Sleep(200 * time.Millisecond)
				return nil
			}
		}
	}
}

func resolveNativeBin() (string, error) {
	// 1. TINGLY_CU_NATIVE env override (set by Taskfile for dev).
	if env := os.Getenv("TINGLY_CU_NATIVE"); env != "" {
		if _, err := os.Stat(env); err == nil {
			return env, nil
		}
	}
	// 2. Look alongside this binary.
	if exe, err := os.Executable(); err == nil {
		candidate := filepath.Join(filepath.Dir(exe), "tingly-cu-native")
		if _, err := os.Stat(candidate); err == nil {
			return candidate, nil
		}
	}
	// 3. PATH lookup.
	if path, err := exec.LookPath("tingly-cu-native"); err == nil {
		return path, nil
	}
	return "", fmt.Errorf("tingly-cu-native not found alongside binary or on PATH; " +
		"build the Swift package first: cd tingly-computer-use/swift && swift build -c release")
}
