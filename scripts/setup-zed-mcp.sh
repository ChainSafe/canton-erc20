#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Zed MCP Server Setup Script
# =============================================================================
# This script sets up the MCP proxy for connecting Zed to a remote MCP server.
#
# Usage:
#   ./scripts/setup-zed-mcp.sh [MCP_SERVER_URL]
#
# Example:
#   ./scripts/setup-zed-mcp.sh http://91.99.186.83:7284/mcp
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MCP_PROXY="${SCRIPT_DIR}/mcp-proxy.js"

# Default MCP server URL
DEFAULT_MCP_URL="http://91.99.186.83:7284/mcp"
MCP_SERVER_URL="${1:-$DEFAULT_MCP_URL}"

# Zed config directory
if [[ "$OSTYPE" == "darwin"* ]]; then
  ZED_CONFIG_DIR="$HOME/Library/Application Support/Zed"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  ZED_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zed"
else
  echo "❌ Unsupported operating system: $OSTYPE"
  exit 1
fi

SETTINGS_FILE="${ZED_CONFIG_DIR}/settings.json"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
  echo -e "${BLUE}[setup]${NC} $*"
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
log "Setting up Zed MCP integration for Canton-ERC20"
echo ""

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
  error "Node.js is not installed"
  echo ""
  echo "Please install Node.js first:"
  echo "  macOS: brew install node"
  echo "  Linux: apt-get install nodejs"
  echo ""
  exit 1
fi

success "Node.js found: $(node --version)"

# Check if MCP proxy exists
if [[ ! -f "$MCP_PROXY" ]]; then
  error "MCP proxy script not found: $MCP_PROXY"
  exit 1
fi

success "MCP proxy script found"

# Test if MCP proxy is executable
if [[ ! -x "$MCP_PROXY" ]]; then
  log "Making MCP proxy executable..."
  chmod +x "$MCP_PROXY"
fi

success "MCP proxy is executable"

# Test remote MCP server connectivity
log "Testing connection to MCP server: $MCP_SERVER_URL"
if curl -s --connect-timeout 5 -X POST "$MCP_SERVER_URL" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"ping","id":1}' &> /dev/null; then
  success "MCP server is reachable"
else
  warn "Unable to connect to MCP server (this may be normal if the server requires authentication)"
fi

# Create Zed config directory if it doesn't exist
if [[ ! -d "$ZED_CONFIG_DIR" ]]; then
  log "Creating Zed config directory: $ZED_CONFIG_DIR"
  mkdir -p "$ZED_CONFIG_DIR"
fi

# Check if settings.json exists
if [[ ! -f "$SETTINGS_FILE" ]]; then
  log "Creating new Zed settings.json"
  cat > "$SETTINGS_FILE" << 'EOF'
{
  "context_servers": {}
}
EOF
fi

# Backup existing settings
BACKUP_FILE="${SETTINGS_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
log "Backing up existing settings to: $(basename "$BACKUP_FILE")"
cp "$SETTINGS_FILE" "$BACKUP_FILE"

# Check if canton-mcp is already configured
if grep -q '"canton-mcp"' "$SETTINGS_FILE" 2>/dev/null; then
  warn "Canton MCP configuration already exists in settings.json"
  echo ""
  read -p "Do you want to update it? (y/n) " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Skipping configuration update"
    exit 0
  fi
fi

# Add or update MCP configuration
log "Updating Zed settings.json..."

# Use Python to safely update JSON
python3 << EOF
import json
import sys

settings_file = "$SETTINGS_FILE"
mcp_proxy = "$MCP_PROXY"
mcp_url = "$MCP_SERVER_URL"

try:
    with open(settings_file, 'r') as f:
        settings = json.load(f)
except json.JSONDecodeError:
    print("Error: Invalid JSON in settings file", file=sys.stderr)
    sys.exit(1)

# Ensure context_servers exists
if 'context_servers' not in settings:
    settings['context_servers'] = {}

# Add canton-mcp configuration
settings['context_servers']['canton-mcp'] = {
    'command': 'node',
    'args': [mcp_proxy, mcp_url]
}

# Write back
with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)

print("✓ Configuration updated successfully")
EOF

if [[ $? -eq 0 ]]; then
  success "Zed settings.json updated"
else
  error "Failed to update settings.json"
  log "Restoring backup..."
  cp "$BACKUP_FILE" "$SETTINGS_FILE"
  exit 1
fi

# Summary
echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
success "MCP proxy configured in Zed"
echo ""
echo "Configuration:"
echo "  MCP Server: $MCP_SERVER_URL"
echo "  Proxy Script: $MCP_PROXY"
echo "  Settings File: $SETTINGS_FILE"
echo "  Backup: $BACKUP_FILE"
echo ""
echo "Next steps:"
echo "  1. Restart Zed editor (fully quit and reopen)"
echo "  2. Open a DAML file in canton-erc20/daml/"
echo "  3. Open Assistant panel: Cmd+? (macOS) or Ctrl+? (Linux)"
echo "  4. Check for 'canton-mcp' in context servers"
echo ""
echo "Troubleshooting:"
echo "  - View logs: tail -f ~/Library/Logs/Zed/Zed.log (macOS)"
echo "  - Test proxy: echo '{\"jsonrpc\":\"2.0\",\"method\":\"ping\",\"id\":1}' | node $MCP_PROXY $MCP_SERVER_URL"
echo "  - Documentation: docs/ZED_MCP_SETUP.md"
echo ""

# Test the proxy
echo "Testing MCP proxy..."
if echo '{"jsonrpc":"2.0","method":"ping","id":1}' | timeout 5 node "$MCP_PROXY" "$MCP_SERVER_URL" 2>/dev/null | grep -q "jsonrpc"; then
  success "MCP proxy test passed"
else
  warn "MCP proxy test failed (this may be normal if the server doesn't support ping)"
fi

echo ""
success "Setup complete! Restart Zed to activate the MCP connection."
echo ""
