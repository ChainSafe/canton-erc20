#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Deploy Canton ERC-20 Bridge to Canton Network Quickstart
# =============================================================================
# This script helps deploy DAR packages to Canton Network quickstart.
#
# Prerequisites:
#   1. Canton Network quickstart set up at ../cn-quickstart
#   2. Nix and direnv installed
#   3. DAR files built (run ./scripts/build-all.sh first)
#
# Usage:
#   ./scripts/deploy-canton.sh [setup|build|deploy|start|stop]
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DAML_DIR="${REPO_ROOT}/daml"
QUICKSTART_DIR="${REPO_ROOT}/../cn-quickstart/quickstart"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[canton]${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }

# Ensure Nix is in PATH
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

# =============================================================================
# Functions
# =============================================================================

check_prerequisites() {
  log "Checking prerequisites..."

  if ! command -v nix &> /dev/null; then
    error "Nix not found. Install with: sh <(curl -L https://nixos.org/nix/install) --daemon"
    exit 1
  fi

  if ! command -v direnv &> /dev/null; then
    error "direnv not found. Install with: sudo apt-get install direnv"
    exit 1
  fi

  if ! command -v docker &> /dev/null; then
    error "Docker not found"
    exit 1
  fi

  if [[ ! -d "${QUICKSTART_DIR}" ]]; then
    error "Canton quickstart not found at ${QUICKSTART_DIR}"
    echo "Clone it with: git clone https://github.com/digital-asset/cn-quickstart.git ${REPO_ROOT}/../cn-quickstart"
    exit 1
  fi

  success "Prerequisites OK"
}

build_dars() {
  log "Building DAR packages..."

  local packages=(
    "common"
    "cip56-token"
    "bridge-core"
    "bridge-wayfinder"
    "bridge-usdc"
    "bridge-cbtc"
    "bridge-generic"
    "dvp"
  )

  for pkg in "${packages[@]}"; do
    local pkg_dir="${DAML_DIR}/${pkg}"
    if [[ -d "${pkg_dir}" ]]; then
      log "Building ${pkg}..."
      cd "${pkg_dir}"
      ~/.daml/bin/daml build --no-legacy-assistant-warning 2>&1 | grep -E "(Created|error)" || true
    fi
  done

  success "All DAR packages built"
}

copy_dars_to_quickstart() {
  log "Copying DAR files to Canton quickstart..."

  # Create target directory
  local target_dir="${QUICKSTART_DIR}/daml/canton-erc20"
  mkdir -p "${target_dir}"

  # Copy all DAR files
  local packages=(
    "common"
    "cip56-token"
    "bridge-core"
    "bridge-wayfinder"
    "bridge-usdc"
    "bridge-cbtc"
    "bridge-generic"
    "dvp"
  )

  for pkg in "${packages[@]}"; do
    local dar_file="${DAML_DIR}/${pkg}/.daml/dist/${pkg}-v2-1.1.0.dar"
    if [[ -f "${dar_file}" ]]; then
      cp "${dar_file}" "${target_dir}/"
      success "Copied ${pkg}-v2-1.1.0.dar"
    else
      warn "DAR not found: ${dar_file}"
    fi
  done

  log "DAR files copied to: ${target_dir}"
}

setup_quickstart() {
  log "Setting up Canton quickstart..."

  cd "${QUICKSTART_DIR}"

  # Allow direnv
  direnv allow 2>/dev/null || true

  # Run setup
  log "Running make setup (interactive)..."
  echo ""
  echo "Configuration tips:"
  echo "  - Observability: n (disable for faster startup)"
  echo "  - OAuth2: y (enable)"
  echo "  - Party Hint: leave blank"
  echo "  - TEST MODE: n (disable)"
  echo ""

  make setup

  success "Setup complete"
}

build_quickstart() {
  log "Building Canton quickstart..."

  cd "${QUICKSTART_DIR}"
  make build

  success "Build complete"
}

start_quickstart() {
  log "Starting Canton quickstart..."

  cd "${QUICKSTART_DIR}"

  echo ""
  echo "Starting Canton Network services..."
  echo "This may take a few minutes on first run."
  echo ""
  echo "In separate terminals, you can run:"
  echo "  make canton-console  # Canton console"
  echo "  make shell           # Daml shell"
  echo "  make capture-logs    # View logs"
  echo ""

  make start
}

stop_quickstart() {
  log "Stopping Canton quickstart..."

  cd "${QUICKSTART_DIR}"
  make stop

  success "Services stopped"
}

show_help() {
  echo "Canton ERC-20 Bridge - Canton Deployment Script"
  echo ""
  echo "Usage: $0 [command]"
  echo ""
  echo "Commands:"
  echo "  check     Check prerequisites"
  echo "  build     Build all DAR packages"
  echo "  copy      Copy DAR files to quickstart"
  echo "  setup     Run Canton quickstart setup (interactive)"
  echo "  compile   Build Canton quickstart"
  echo "  start     Start Canton services"
  echo "  stop      Stop Canton services"
  echo "  all       Run full deployment (build + copy + setup + compile + start)"
  echo "  help      Show this help"
  echo ""
  echo "Examples:"
  echo "  $0 check    # Verify prerequisites"
  echo "  $0 build    # Build DAR files"
  echo "  $0 all      # Full deployment"
}

# =============================================================================
# Main
# =============================================================================

case "${1:-help}" in
  check)
    check_prerequisites
    ;;
  build)
    build_dars
    ;;
  copy)
    copy_dars_to_quickstart
    ;;
  setup)
    check_prerequisites
    setup_quickstart
    ;;
  compile)
    build_quickstart
    ;;
  start)
    start_quickstart
    ;;
  stop)
    stop_quickstart
    ;;
  all)
    check_prerequisites
    build_dars
    copy_dars_to_quickstart
    setup_quickstart
    build_quickstart
    start_quickstart
    ;;
  help|*)
    show_help
    ;;
esac
