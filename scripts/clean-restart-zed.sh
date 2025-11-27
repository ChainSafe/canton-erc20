#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Clean Restart Script for Zed MCP Connection
# =============================================================================
# This script performs a complete clean restart of Zed to ensure MCP
# configuration is loaded fresh without any cached state.
#
# Usage:
#   ./scripts/clean-restart-zed.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
  echo -e "${BLUE}[clean-restart]${NC} $*"
}

success() {
  echo -e "${GREEN}✓${NC} $*"
}

error() {
  echo -e "${RED}✗${NC} $*"
}

warn() {
  echo -e "${YELLOW}⚠${NC} $*"
}

# =============================================================================
# Main
# =============================================================================

echo ""
log "Starting clean restart procedure for Zed MCP connection..."
echo ""

# Step 1: Quit Zed
log "Step 1: Quitting Zed completely..."
if pgrep -x "Zed" > /dev/null; then
  killall -9 Zed 2>/dev/null || true
  sleep 3
  if pgrep -x "Zed" > /dev/null; then
    error "Zed is still running. Please quit manually."
    exit 1
  fi
  success "Zed terminated"
else
  success "Zed not running"
fi

# Step 2: Clear caches
log "Step 2: Clearing Zed caches and state..."
rm -rf ~/Library/Caches/dev.zed.Zed 2>/dev/null || true
rm -rf ~/Library/Application\ Support/Zed/db 2>/dev/null || true
rm -rf /tmp/zed-* 2>/dev/null || true
success "Caches cleared"

# Step 3: Clear debug log
log "Step 3: Clearing debug log..."
rm -f /tmp/mcp-proxy-debug.log
touch /tmp/mcp-proxy-debug.log
success "Debug log ready"

# Step 4: Verify scripts are executable
log "Step 4: Verifying scripts are executable..."
chmod +x "${SCRIPT_DIR}/mcp-proxy-debug.sh" 2>/dev/null || true
chmod +x "${SCRIPT_DIR}/mcp-proxy.js" 2>/dev/null || true

if [[ -x "${SCRIPT_DIR}/mcp-proxy-debug.sh" ]]; then
  success "mcp-proxy-debug.sh is executable"
else
  error "mcp-proxy-debug.sh is not executable"
  exit 1
fi

if [[ -x "${SCRIPT_DIR}/mcp-proxy.js" ]]; then
  success "mcp-proxy.js is executable"
else
  error "mcp-proxy.js is not executable"
  exit 1
fi

# Step 5: Verify settings
log "Step 5: Verifying Zed settings..."
SETTINGS_FILE="$HOME/Library/Application Support/Zed/settings.json"

if [[ ! -f "$SETTINGS_FILE" ]]; then
  error "Settings file not found: $SETTINGS_FILE"
  exit 1
fi

if grep -q "canton-mcp" "$SETTINGS_FILE"; then
  success "canton-mcp configuration found in settings.json"
else
  error "canton-mcp not found in settings.json"
  echo ""
  echo "Expected configuration:"
  echo '{'
  echo '  "context_servers": {'
  echo '    "canton-mcp": {'
  echo '      "command": "/Users/s3b/Dev/canton-erc20/scripts/mcp-proxy-debug.sh",'
  echo '      "args": ["http://91.99.186.83:7284/mcp"]'
  echo '    }'
  echo '  }'
  echo '}'
  exit 1
fi

# Step 6: Test proxy manually
log "Step 6: Testing proxy manually..."
TEST_RESULT=$(cd "$REPO_ROOT" && (echo '{"jsonrpc":"2.0","method":"initialize","id":0,"params":{}}'; sleep 2) | \
  node scripts/mcp-proxy.js http://91.99.186.83:7284/mcp 2>&1 | grep -c "Response received: 200" || echo "0")

if [[ "$TEST_RESULT" -gt 0 ]]; then
  success "Proxy test passed"
else
  warn "Proxy test did not show expected response (may still work)"
fi

# Step 7: Instructions
echo ""
echo "=========================================="
echo "Clean Restart Complete!"
echo "=========================================="
echo ""
success "Zed is ready to restart with clean state"
echo ""
echo "Next steps:"
echo ""
echo "  1. Open TWO terminal windows:"
echo ""
echo "     Terminal 1 - Watch debug log:"
echo "     $ tail -f /tmp/mcp-proxy-debug.log"
echo ""
echo "     Terminal 2 - Watch Zed log:"
echo "     $ tail -f ~/Library/Logs/Zed/Zed.log"
echo ""
echo "  2. Open Zed:"
echo "     $ open -a Zed"
echo ""
echo "  3. Watch the logs for:"
echo "     ✓ 'Starting context server: canton-mcp'"
echo "     ✓ 'MCP proxy initialized and ready'"
echo "     ✓ 'Response received: 200'"
echo ""
echo "  4. Test in Zed Assistant (Cmd+?):"
echo "     Ask: 'What is a CIP-56 token?'"
echo ""
echo "=========================================="
echo ""

# Offer to start monitoring
read -p "Start monitoring logs and open Zed now? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
  log "Starting log monitoring..."

  # Open terminals with log monitoring
  osascript <<EOF 2>/dev/null || true
    tell application "Terminal"
      do script "tail -f /tmp/mcp-proxy-debug.log"
      do script "tail -f ~/Library/Logs/Zed/Zed.log"
    end tell
EOF

  sleep 2

  log "Opening Zed..."
  open -a Zed

  echo ""
  success "Zed started! Watch the terminal windows for log output."
  echo ""
else
  log "Manual start - follow the instructions above"
fi

echo ""
log "Clean restart procedure complete"
echo ""
