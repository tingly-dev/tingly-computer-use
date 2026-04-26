#!/bin/bash
# Generate Go and Swift proto/gRPC code from computeruse.proto
# Prerequisites:
#   go: protoc, protoc-gen-go, protoc-gen-go-grpc
#   swift: protoc-gen-swift, protoc-gen-grpc-swift (from grpc-swift v2)
#
# Install Go plugins:
#   go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
#   go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
#
# Install Swift plugins (via Homebrew or build from grpc-swift):
#   brew install swift-protobuf grpc-swift

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
PROTO_DIR="$ROOT/proto"
GO_OUT="$ROOT/pkg/proto"
SWIFT_OUT="$ROOT/swift/Sources/TinglyComputerUseKit/Generated"

echo "==> Generating Go proto code..."
mkdir -p "$GO_OUT"
protoc \
  --proto_path="$PROTO_DIR" \
  --go_out="$GO_OUT" \
  --go_opt=paths=source_relative \
  --go-grpc_out="$GO_OUT" \
  --go-grpc_opt=paths=source_relative \
  computeruse/v1/computeruse.proto

echo "==> Generating Swift proto code..."
mkdir -p "$SWIFT_OUT"
protoc \
  --proto_path="$PROTO_DIR" \
  --swift_out="$SWIFT_OUT" \
  --swift_opt=Visibility=Public \
  --grpc-swift-2_out="$SWIFT_OUT" \
  --grpc-swift-2_opt=Visibility=Public \
  computeruse/v1/computeruse.proto

echo "==> Done."
echo "    Go:    $GO_OUT/computeruse/v1/"
echo "    Swift: $SWIFT_OUT/"
