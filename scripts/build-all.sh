#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Build All Packages (DAML + Solidity)
# =============================================================================
# This script builds all DAML packages in the correct dependency order,
# and optionally builds Solidity contracts.
#
# Usage:
#   ./scripts/build-all.sh [--clean] [--verbose] [--solidity] [--daml-only]
#
# Options:
#   --clean       Run daml clean before building each package
#   --verbose     Show detailed build output
#   --solidity    Also build Solidity contracts (requires Foundry)
#   --daml-only   Only build DAML packages (skip Solidity even if --solidity)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DAML_DIR="${REPO_ROOT}/daml"
ETHEREUM_DIR="${REPO_ROOT}/ethereum"

# Parse arguments
CLEAN=false
VERBOSE=false
BUILD_SOLIDITY=false
DAML_ONLY=false

for arg in "$@"; do
  case $arg in
    --clean)
      CLEAN=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --solidity)
      BUILD_SOLIDITY=true
      shift
      ;;
    --daml-only)
      DAML_ONLY=true
      shift
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Usage: $0 [--clean] [--verbose] [--solidity] [--daml-only]"
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
  echo -e "${BLUE}[build]${NC} $*"
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

# Build a single package
build_package() {
  local pkg_name="$1"
  local pkg_dir="${DAML_DIR}/${pkg_name}"

  if [[ ! -d "${pkg_dir}" ]]; then
    warn "Package directory not found: ${pkg_name} (skipping)"
    return 0
  fi

  if [[ ! -f "${pkg_dir}/daml.yaml" ]]; then
    warn "No daml.yaml found in ${pkg_name} (skipping)"
    return 0
  fi

  log "Building ${pkg_name}..."

  cd "${pkg_dir}"

  # Clean if requested
  if [[ "${CLEAN}" == "true" ]]; then
    daml clean 2>/dev/null || true
  fi

  # Build
  if [[ "${VERBOSE}" == "true" ]]; then
    if daml build; then
      success "${pkg_name} built successfully"
      return 0
    else
      error "Failed to build ${pkg_name}"
      return 1
    fi
  else
    if daml build 2>&1 | grep -E "(ERROR|error|Created .*.dar)" ; then
      success "${pkg_name} built successfully"
      return 0
    else
      error "Failed to build ${pkg_name}"
      return 1
    fi
  fi
}

# =============================================================================
# Main
# =============================================================================

log "Building all DAML packages in dependency order..."
echo ""

# Package build order (respects dependencies)
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

FAILED_PACKAGES=()
BUILT_COUNT=0
SKIPPED_COUNT=0

for pkg in "${PACKAGES[@]}"; do
  if build_package "$pkg"; then
    BUILT_COUNT=$((BUILT_COUNT + 1))
  else
    FAILED_PACKAGES+=("$pkg")
  fi
  echo ""
done

# Summary
echo ""
echo "=========================================="
echo "Build Summary"
echo "=========================================="
echo "Total packages: ${#PACKAGES[@]}"
echo "Built successfully: ${BUILT_COUNT}"
echo "Failed: ${#FAILED_PACKAGES[@]}"
echo ""

if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
  error "Failed packages:"
  for pkg in "${FAILED_PACKAGES[@]}"; do
    echo "  - $pkg"
  done
  echo ""
  exit 1
else
  success "All DAML packages built successfully!"
  echo ""
  echo "DARs created in:"
  for pkg in "${PACKAGES[@]}"; do
    dar_path="${DAML_DIR}/${pkg}/.daml/dist/${pkg}-1.0.0.dar"
    if [[ -f "$dar_path" ]]; then
      size=$(du -h "$dar_path" | cut -f1)
      echo "  - ${pkg}/.daml/dist/${pkg}-1.0.0.dar (${size})"
    fi
  done
  echo ""
fi

# =============================================================================
# Build Solidity Contracts (if requested)
# =============================================================================

build_solidity() {
  if [[ ! -d "${ETHEREUM_DIR}" ]]; then
    warn "Ethereum directory not found: ${ETHEREUM_DIR}"
    return 1
  fi

  log "Building Solidity contracts..."
  cd "${ETHEREUM_DIR}"

  # Check for Foundry
  local FORGE_CMD=""
  if command -v forge &> /dev/null; then
    FORGE_CMD="forge"
  elif [[ -f "$HOME/.foundry/bin/forge" ]]; then
    FORGE_CMD="$HOME/.foundry/bin/forge"
  else
    error "Foundry not found. Install it with: curl -L https://foundry.paradigm.xyz | bash"
    return 1
  fi

  # Clean if requested
  if [[ "${CLEAN}" == "true" ]]; then
    ${FORGE_CMD} clean 2>/dev/null || true
  fi

  # Build
  if [[ "${VERBOSE}" == "true" ]]; then
    if ${FORGE_CMD} build; then
      success "Solidity contracts built successfully"
      return 0
    else
      error "Failed to build Solidity contracts"
      return 1
    fi
  else
    if ${FORGE_CMD} build 2>&1 | grep -E "(Compiling|Compiler|error|warning)" || true; then
      success "Solidity contracts built successfully"
      return 0
    else
      error "Failed to build Solidity contracts"
      return 1
    fi
  fi
}

if [[ "${BUILD_SOLIDITY}" == "true" && "${DAML_ONLY}" != "true" ]]; then
  echo ""
  echo "=========================================="
  echo "Building Solidity Contracts"
  echo "=========================================="
  echo ""
  if ! build_solidity; then
    error "Solidity build failed"
    exit 1
  fi
  echo ""
  success "All builds completed!"
fi

if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
  exit 1
fi

exit 0
