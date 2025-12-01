#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Test All DAML Packages
# =============================================================================
# This script runs tests for all DAML packages in the correct dependency order.
#
# Usage:
#   ./scripts/test-all.sh [--verbose] [--package PACKAGE_NAME]
#
# Options:
#   --verbose              Show detailed test output
#   --package PACKAGE_NAME Run tests only for specific package
#   --coverage             Generate coverage report
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DAML_DIR="${REPO_ROOT}/daml"

# Parse arguments
VERBOSE=false
SPECIFIC_PACKAGE=""
COVERAGE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose)
      VERBOSE=true
      shift
      ;;
    --package)
      SPECIFIC_PACKAGE="$2"
      shift 2
      ;;
    --coverage)
      COVERAGE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--verbose] [--package PACKAGE_NAME] [--coverage]"
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
  echo -e "${BLUE}[test]${NC} $*"
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

# Test a single package
test_package() {
  local pkg_name="$1"
  local pkg_dir="${DAML_DIR}/${pkg_name}"

  if [[ ! -d "${pkg_dir}" ]]; then
    warn "Package directory not found: ${pkg_name} (skipping)"
    return 2
  fi

  if [[ ! -f "${pkg_dir}/daml.yaml" ]]; then
    warn "No daml.yaml found in ${pkg_name} (skipping)"
    return 2
  fi

  log "Testing ${pkg_name}..."

  cd "${pkg_dir}"

  # Check if package has test files
  if ! find . -name "*.daml" -type f -exec grep -l "^test" {} \; | grep -q .; then
    warn "${pkg_name} has no tests (skipping)"
    return 2
  fi

  # Build test command
  local test_cmd="daml test"

  if [[ "${COVERAGE}" == "true" ]]; then
    test_cmd="${test_cmd} --show-coverage"
  fi

  # Run tests
  if [[ "${VERBOSE}" == "true" ]]; then
    if ${test_cmd}; then
      success "${pkg_name} tests passed"
      return 0
    else
      error "${pkg_name} tests failed"
      return 1
    fi
  else
    local output
    if output=$(${test_cmd} 2>&1); then
      # Extract summary
      local summary=$(echo "$output" | grep -E "(tests passed|test passed|All.*passed)" || echo "Tests completed")
      success "${pkg_name}: ${summary}"
      return 0
    else
      error "${pkg_name} tests failed"
      echo "$output" | grep -E "(FAIL|ERROR|error)" || echo "$output"
      return 1
    fi
  fi
}

# =============================================================================
# Main
# =============================================================================

if [[ -n "${SPECIFIC_PACKAGE}" ]]; then
  log "Running tests for package: ${SPECIFIC_PACKAGE}"
  echo ""
  if test_package "${SPECIFIC_PACKAGE}"; then
    exit 0
  else
    exit 1
  fi
fi

log "Running tests for all DAML packages..."
echo ""

# Package test order (same as build order)
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
PASSED_COUNT=0
SKIPPED_COUNT=0

for pkg in "${PACKAGES[@]}"; do
  result=0
  test_package "$pkg" || result=$?

  if [[ $result -eq 0 ]]; then
    PASSED_COUNT=$((PASSED_COUNT + 1))
  elif [[ $result -eq 2 ]]; then
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
  else
    FAILED_PACKAGES+=("$pkg")
  fi
  echo ""
done

# Summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Total packages: ${#PACKAGES[@]}"
echo "Tests passed: ${PASSED_COUNT}"
echo "Tests skipped: ${SKIPPED_COUNT}"
echo "Tests failed: ${#FAILED_PACKAGES[@]}"
echo ""

if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
  error "Failed packages:"
  for pkg in "${FAILED_PACKAGES[@]}"; do
    echo "  - $pkg"
  done
  echo ""
  exit 1
else
  if [[ ${PASSED_COUNT} -eq 0 ]]; then
    warn "No tests were run. Consider adding test scripts to your packages."
    echo ""
    echo "To add tests, create scripts in your DAML files:"
    echo ""
    echo "  test myTest : Script ()"
    echo "  test myTest = script do"
    echo "    -- your test code"
    echo ""
  else
    success "All tests passed!"
  fi
  echo ""
  exit 0
fi
