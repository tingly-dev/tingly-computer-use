#!/bin/bash
# Build all components of tingly-computer-use.
# Prerequisites: Xcode CLT, Go 1.23+, protoc with plugins (see gen-proto.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."

echo "==> Step 1: Generate proto code"
bash "$SCRIPT_DIR/gen-proto.sh"

echo "==> Step 2: Build Swift native layer"
cd "$ROOT/swift"
swift build --product tingly-cu-native -c release
SWIFT_BIN="$(swift build --product tingly-cu-native -c release --show-bin-path)/tingly-cu-native"
echo "    Binary: $SWIFT_BIN"

echo "==> Step 3: Build Go MCP server"
cd "$ROOT/go"
go mod tidy
go build -o tingly-cu ./cmd/tingly-cu
echo "    Binary: $ROOT/go/tingly-cu"

echo ""
echo "==> Build complete."
echo "    Swift: $SWIFT_BIN"
echo "    Go:    $ROOT/go/tingly-cu"
echo ""
echo "To test: copy both binaries to the same directory and run:"
echo "    ./tingly-cu doctor    # check permissions"
echo "    ./tingly-cu mcp       # start MCP stdio server"
