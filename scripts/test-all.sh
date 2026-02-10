#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Test All Packages (DAML + Solidity)
# =============================================================================
# This script runs tests for all DAML test packages and optionally Solidity.
#
# Usage:
#   ./scripts/test-all.sh [--verbose] [--package PACKAGE_NAME] [--solidity] [--daml-only]
#
# Options:
#   --verbose              Show detailed test output
#   --package PACKAGE_NAME Run tests only for specific package
#   --coverage             Generate coverage report
#   --solidity             Also run Solidity tests (requires Foundry)
#   --daml-only            Only run DAML tests (skip Solidity)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DAML_DIR="${REPO_ROOT}/daml"
ETHEREUM_DIR="${REPO_ROOT}/ethereum"

# Parse arguments
VERBOSE=false
SPECIFIC_PACKAGE=""
COVERAGE=false
TEST_SOLIDITY=false
DAML_ONLY=false

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
    --solidity)
      TEST_SOLIDITY=true
      shift
      ;;
    --daml-only)
      DAML_ONLY=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--verbose] [--package PACKAGE_NAME] [--coverage] [--solidity] [--daml-only]"
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
  echo -e "${GREEN}[OK]${NC} $*"
}

error() {
  echo -e "${RED}[FAIL]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
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

log "Running tests for all DAML test packages..."
echo ""

# Test packages (these contain daml-script test scripts)
PACKAGES=(
  "common-tests"
  "cip56-token-tests"
  "bridge-core-tests"
  "bridge-wayfinder-tests"
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

DAML_FAILED=false
if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
  error "Failed DAML packages:"
  for pkg in "${FAILED_PACKAGES[@]}"; do
    echo "  - $pkg"
  done
  echo ""
  DAML_FAILED=true
else
  if [[ ${PASSED_COUNT} -eq 0 ]]; then
    warn "No DAML tests were run. Consider adding test scripts to your packages."
    echo ""
  else
    success "All DAML tests passed!"
  fi
fi

# =============================================================================
# Solidity Tests (if requested)
# =============================================================================

test_solidity() {
  if [[ ! -d "${ETHEREUM_DIR}" ]]; then
    warn "Ethereum directory not found: ${ETHEREUM_DIR}"
    return 1
  fi

  log "Running Solidity tests..."
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

  # Run tests
  local test_args="-vv"
  if [[ "${VERBOSE}" == "true" ]]; then
    test_args="-vvvv"
  fi

  if ${FORGE_CMD} test ${test_args}; then
    success "Solidity tests passed"
    return 0
  else
    error "Solidity tests failed"
    return 1
  fi
}

SOLIDITY_FAILED=false
if [[ "${TEST_SOLIDITY}" == "true" && "${DAML_ONLY}" != "true" ]]; then
  echo ""
  echo "=========================================="
  echo "Solidity Tests"
  echo "=========================================="
  echo ""
  if ! test_solidity; then
    SOLIDITY_FAILED=true
  fi
fi

# Final summary
echo ""
if [[ "${DAML_FAILED}" == "true" || "${SOLIDITY_FAILED}" == "true" ]]; then
  error "Some tests failed"
  exit 1
else
  success "All tests completed successfully!"
  exit 0
fi
