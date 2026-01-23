#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Deploy Canton Bridge to Ethereum Sepolia Testnet
# =============================================================================
# Usage: ./scripts/deploy-testnet.sh
#
# Prerequisites:
#   1. Copy .env.example to .env and fill in your values
#   2. Get Sepolia ETH from a faucet
#   3. Have Foundry installed
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETHEREUM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[deploy]${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }

cd "${ETHEREUM_DIR}"

# Check for .env file
if [[ ! -f ".env" ]]; then
  error ".env file not found!"
  echo ""
  echo "Please create .env from .env.example:"
  echo "  cp .env.example .env"
  echo "  # Edit .env with your values"
  exit 1
fi

# Load environment
source .env

# Validate required variables
if [[ -z "${PRIVATE_KEY:-}" ]]; then
  error "PRIVATE_KEY not set in .env"
  exit 1
fi

if [[ -z "${SEPOLIA_RPC_URL:-}" ]]; then
  error "SEPOLIA_RPC_URL not set in .env"
  echo ""
  echo "Free RPC endpoints:"
  echo "  - https://rpc.sepolia.org (public)"
  echo "  - https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY (Alchemy)"
  exit 1
fi

# Find forge
FORGE_CMD=""
if command -v forge &> /dev/null; then
  FORGE_CMD="forge"
elif [[ -f "$HOME/.foundry/bin/forge" ]]; then
  FORGE_CMD="$HOME/.foundry/bin/forge"
else
  error "Foundry not found. Install with: curl -L https://foundry.paradigm.xyz | bash"
  exit 1
fi

echo ""
echo "=========================================="
echo "Canton Bridge - Ethereum Sepolia Deployment"
echo "=========================================="
echo ""

# Get deployer address
DEPLOYER_ADDRESS=$(cast wallet address --private-key "${PRIVATE_KEY}" 2>/dev/null || echo "unknown")
log "Deployer: ${DEPLOYER_ADDRESS}"
log "Network: Ethereum Sepolia (Chain ID: 11155111)"
log "RPC: ${SEPOLIA_RPC_URL}"
echo ""

# Check balance
log "Checking balance..."
BALANCE=$(cast balance "${DEPLOYER_ADDRESS}" --rpc-url "${SEPOLIA_RPC_URL}" 2>/dev/null || echo "0")
BALANCE_ETH=$(echo "scale=4; ${BALANCE} / 1000000000000000000" | bc 2>/dev/null || echo "unknown")
log "Balance: ${BALANCE_ETH} ETH"

if [[ "${BALANCE}" == "0" ]]; then
  error "Insufficient balance! Get testnet ETH from:"
  echo "  - https://cloud.google.com/application/web3/faucet/ethereum/sepolia"
  echo "  - https://sepolia-faucet.pk910.de/"
  echo "  - https://faucets.chain.link/sepolia"
  exit 1
fi

echo ""
log "Deploying contracts..."
echo ""

# Deploy
${FORGE_CMD} script script/Deploy.s.sol:DeployCantonBridge \
  --rpc-url "${SEPOLIA_RPC_URL}" \
  --broadcast \
  -vvv

echo ""
success "Deployment complete!"
echo ""
echo "Next steps:"
echo "  1. Save the deployed addresses"
echo "  2. Register tokens with RegisterToken script"
echo "  3. Set rate limits with SetRateLimit script"
echo ""
