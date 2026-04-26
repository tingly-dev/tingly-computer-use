// Package tools implements MCP tool handlers that delegate to the bridge client.
package tools

import (
	"github.com/tingly-dev/tingly-computer-use/internal/bridge"
)

// Handlers holds all tool handler methods.
type Handlers struct {
	client *bridge.Client
}

// NewHandlers creates a Handlers backed by the given bridge client.
func NewHandlers(client *bridge.Client) *Handlers {
	return &Handlers{client: client}
}
