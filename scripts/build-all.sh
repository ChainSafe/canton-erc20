#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Build All DAML Packages
# =============================================================================
# This script builds all DAML packages in the correct dependency order.
#
# Usage:
#   ./scripts/build-all.sh [--clean] [--verbose]
#
# Options:
#   --clean     Run daml clean before building each package
#   --verbose   Show detailed build output
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DAML_DIR="${REPO_ROOT}/daml"

# Parse arguments
CLEAN=false
VERBOSE=false

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
    *)
      echo "Unknown option: $arg"
      echo "Usage: $0 [--clean] [--verbose]"
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
    if daml build --enable-multi-package=no; then
      success "${pkg_name} built successfully"
      return 0
    else
      error "Failed to build ${pkg_name}"
      return 1
    fi
  else
    if daml build --enable-multi-package=no 2>&1 | grep -E "(ERROR|error|Created .*.dar)" ; then
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
  success "All packages built successfully!"
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
  exit 0
fi
