#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Clean All Packages (DAML + Solidity)
# =============================================================================
# This script removes build artifacts from all packages.
#
# Usage:
#   ./scripts/clean-all.sh [--deep] [--solidity]
#
# Options:
#   --deep      Also remove .daml directory (full clean)
#   --solidity  Also clean Solidity artifacts (requires Foundry)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DAML_DIR="${REPO_ROOT}/daml"
ETHEREUM_DIR="${REPO_ROOT}/ethereum"

# Parse arguments
DEEP_CLEAN=false
CLEAN_SOLIDITY=false

for arg in "$@"; do
  case $arg in
    --deep)
      DEEP_CLEAN=true
      shift
      ;;
    --solidity)
      CLEAN_SOLIDITY=true
      shift
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Usage: $0 [--deep] [--solidity]"
      exit 1
      ;;
  esac
done

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
  echo -e "${BLUE}[clean]${NC} $*"
}

success() {
  echo -e "${GREEN}✓${NC} $*"
}

warn() {
  echo -e "${YELLOW}⚠${NC} $*"
}

# Clean a single package
clean_package() {
  local pkg_name="$1"
  local pkg_dir="${DAML_DIR}/${pkg_name}"

  if [[ ! -d "${pkg_dir}" ]]; then
    return 0
  fi

  if [[ ! -f "${pkg_dir}/daml.yaml" ]]; then
    return 0
  fi

  log "Cleaning ${pkg_name}..."

  cd "${pkg_dir}"

  # Run daml clean
  if daml clean 2>/dev/null; then
    success "${pkg_name} cleaned"
  fi

  # Deep clean if requested
  if [[ "${DEEP_CLEAN}" == "true" ]]; then
    if [[ -d ".daml" ]]; then
      rm -rf .daml
      log "Removed .daml directory from ${pkg_name}"
    fi
  fi
}

# =============================================================================
# Main
# =============================================================================

if [[ "${DEEP_CLEAN}" == "true" ]]; then
  log "Running deep clean (removing all .daml directories)..."
else
  log "Running clean (removing build artifacts)..."
fi
echo ""

# All packages
PACKAGES=(
  "common"
  "cip56-token"
  "bridge-core"
  "bridge-wayfinder"
  "bridge-usdc"
  "bridge-cbtc"
  "bridge-generic"
  "dvp"
  "integration-tests"
)

for pkg in "${PACKAGES[@]}"; do
  clean_package "$pkg"
done

# Also clean the old ERC20 package if it exists
if [[ -d "${DAML_DIR}/ERC20" ]]; then
  log "Cleaning legacy ERC20 package..."
  cd "${DAML_DIR}/ERC20"
  daml clean 2>/dev/null || true
  if [[ "${DEEP_CLEAN}" == "true" && -d ".daml" ]]; then
    rm -rf .daml
  fi
fi

# Clean root daml directory artifacts
cd "${DAML_DIR}"
if [[ -d ".daml" ]]; then
  if [[ "${DEEP_CLEAN}" == "true" ]]; then
    rm -rf .daml
    log "Removed root .daml directory"
  fi
fi

# =============================================================================
# Clean Solidity Artifacts (if requested)
# =============================================================================

clean_solidity() {
  if [[ ! -d "${ETHEREUM_DIR}" ]]; then
    return 0
  fi

  log "Cleaning Solidity artifacts..."
  cd "${ETHEREUM_DIR}"

  # Check for Foundry
  local FORGE_CMD=""
  if command -v forge &> /dev/null; then
    FORGE_CMD="forge"
  elif [[ -f "$HOME/.foundry/bin/forge" ]]; then
    FORGE_CMD="$HOME/.foundry/bin/forge"
  fi

  if [[ -n "${FORGE_CMD}" ]]; then
    ${FORGE_CMD} clean 2>/dev/null || true
    success "Solidity artifacts cleaned"
  else
    # Manual cleanup if forge not available
    rm -rf out cache broadcast 2>/dev/null || true
    success "Solidity artifacts cleaned (manual)"
  fi
}

if [[ "${CLEAN_SOLIDITY}" == "true" ]]; then
  clean_solidity
fi

echo ""
success "Clean complete!"
echo ""

if [[ "${DEEP_CLEAN}" == "true" ]]; then
  echo "All build artifacts and .daml directories removed."
else
  echo "Build artifacts removed."
fi

if [[ "${CLEAN_SOLIDITY}" == "true" ]]; then
  echo "Solidity artifacts also cleaned."
fi

echo "Run './scripts/build-all.sh' to rebuild all packages."
echo ""
