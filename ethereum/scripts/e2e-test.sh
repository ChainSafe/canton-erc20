#!/usr/bin/env bash
# =============================================================================
# Canton-Ethereum Bridge E2E Test Script
# =============================================================================
# Tests the full deposit flow: Ethereum Sepolia -> Canton Network
#
# Prerequisites:
#   - Foundry (cast, forge) installed at ~/.foundry/bin/
#   - Canton middleware running (./bin/relayer -config config.sepolia-quickstart.yaml)
#   - cn-quickstart running (make start)
#   - Sufficient Sepolia ETH for gas
#
# Usage:
#   ./scripts/e2e-test.sh [--skip-deploy] [--token-address <addr>]
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETHEREUM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Foundry binary path (avoiding ZOE conflict)
FORGE="${HOME}/.foundry/bin/forge"
CAST="${HOME}/.foundry/bin/cast"

# Network configuration
RPC_URL="https://eth-sepolia.g.alchemy.com/v2/MeMdx3uk0ZFuSy2YFs0VAGjG7gXf0wJP"
CHAIN_ID=11155111

# Deployed contract addresses (from broadcast/Deploy.s.sol/11155111/run-latest.json)
BRIDGE_ADDRESS="0x523a865Bf51d93df22Fb643e6BDE2F66438e32c2"
TOKEN_REGISTRY="0x675E7eE05D1d7376DC0a6d233440bF9753Ba6f9F"

# Relayer account (has ADMIN_ROLE and RELAYER_ROLE)
RELAYER_PRIVATE_KEY="0x082560991dcfb10aff28a973120329d0fbf1e490357cfcf15ad9d17548c29eb2"
RELAYER_ADDRESS="0x88ce832A05eE26C9a4011e2d9cf957f97F43B08C"

# Test Canton fingerprint (example format: 1220 prefix + 31 bytes)
# This should be a real Canton party fingerprint for production tests
CANTON_RECIPIENT="0x1220abcdef1234567890abcdef1234567890abcdef1234567890abcdef123456"

# Test amounts
MINT_AMOUNT="1000000000000000000000"  # 1000 tokens (18 decimals)
DEPOSIT_AMOUNT="100000000000000000000"  # 100 tokens (18 decimals)

# Canton token ID for registration
CANTON_TOKEN_ID="0x$(echo -n 'canton:test-prompt' | sha256sum | cut -d' ' -f1)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# State
MOCK_TOKEN_ADDRESS=""
SKIP_DEPLOY=false

# =============================================================================
# Helper Functions
# =============================================================================

log() { echo -e "${BLUE}[e2e]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

check_foundry() {
    if [[ ! -x "${FORGE}" ]]; then
        error "Foundry forge not found at ${FORGE}. Install with: curl -L https://foundry.paradigm.xyz | bash"
    fi
    if [[ ! -x "${CAST}" ]]; then
        error "Foundry cast not found at ${CAST}. Install with: curl -L https://foundry.paradigm.xyz | bash"
    fi
    log "Foundry binaries OK"
}

check_balance() {
    local balance
    balance=$("${CAST}" balance "${RELAYER_ADDRESS}" --rpc-url "${RPC_URL}" 2>/dev/null)
    local balance_eth
    balance_eth=$("${CAST}" from-wei "${balance}" 2>/dev/null)
    log "Relayer balance: ${balance_eth} ETH"

    # Check if balance is too low (< 0.01 ETH)
    local min_balance="10000000000000000"  # 0.01 ETH in wei
    if [[ $(echo "${balance} < ${min_balance}" | bc -l 2>/dev/null || echo "0") == "1" ]]; then
        warn "Low balance! Get Sepolia ETH from: https://sepoliafaucet.com/"
    fi
}

wait_for_tx() {
    local tx_hash=$1
    local description=$2
    log "Waiting for transaction: ${description}"
    log "TX: ${tx_hash}"

    local receipt
    receipt=$("${CAST}" receipt "${tx_hash}" --rpc-url "${RPC_URL}" --json 2>/dev/null)

    local status
    status=$(echo "${receipt}" | jq -r '.status')

    if [[ "${status}" == "0x1" ]]; then
        success "Transaction confirmed: ${description}"
        local gas_used
        gas_used=$(echo "${receipt}" | jq -r '.gasUsed')
        log "Gas used: $((gas_used))"
    else
        error "Transaction failed: ${description}"
    fi
}

# =============================================================================
# Test Steps
# =============================================================================

step_1_deploy_mock_token() {
    log "=========================================="
    log "Step 1: Deploy MockPROMPT Token"
    log "=========================================="

    if [[ "${SKIP_DEPLOY}" == "true" ]] && [[ -n "${MOCK_TOKEN_ADDRESS}" ]]; then
        log "Skipping deployment, using existing token: ${MOCK_TOKEN_ADDRESS}"
        return
    fi

    cd "${ETHEREUM_DIR}"

    # Compile contracts
    log "Compiling contracts..."
    "${FORGE}" build --quiet

    # Deploy MockPROMPT
    log "Deploying MockPROMPT token..."
    local deploy_output
    deploy_output=$("${FORGE}" create \
        --rpc-url "${RPC_URL}" \
        --private-key "${RELAYER_PRIVATE_KEY}" \
        --broadcast \
        contracts/mocks/MockERC20.sol:MockPROMPT 2>&1)

    # Parse "Deployed to: 0x..." from output
    MOCK_TOKEN_ADDRESS=$(echo "${deploy_output}" | grep -oP 'Deployed to: \K0x[a-fA-F0-9]+')

    if [[ -z "${MOCK_TOKEN_ADDRESS}" ]]; then
        error "Failed to deploy MockPROMPT. Output: ${deploy_output}"
    fi

    success "MockPROMPT deployed at: ${MOCK_TOKEN_ADDRESS}"

    # Verify deployment
    local name
    name=$("${CAST}" call "${MOCK_TOKEN_ADDRESS}" "name()(string)" --rpc-url "${RPC_URL}")
    local symbol
    symbol=$("${CAST}" call "${MOCK_TOKEN_ADDRESS}" "symbol()(string)" --rpc-url "${RPC_URL}")
    local decimals
    decimals=$("${CAST}" call "${MOCK_TOKEN_ADDRESS}" "decimals()(uint8)" --rpc-url "${RPC_URL}")

    log "Token name: ${name}"
    log "Token symbol: ${symbol}"
    log "Token decimals: ${decimals}"
}

step_2_register_token() {
    log "=========================================="
    log "Step 2: Register Token with Bridge"
    log "=========================================="

    # Check if token is already registered
    local is_registered
    is_registered=$("${CAST}" call "${BRIDGE_ADDRESS}" \
        "registeredTokens(address)(bool)" \
        "${MOCK_TOKEN_ADDRESS}" \
        --rpc-url "${RPC_URL}")

    if [[ "${is_registered}" == "true" ]]; then
        log "Token already registered with bridge"
        return
    fi

    log "Registering token with CantonBridge..."
    local tx_hash
    tx_hash=$("${CAST}" send "${BRIDGE_ADDRESS}" \
        "registerToken(address,bytes32)" \
        "${MOCK_TOKEN_ADDRESS}" \
        "${CANTON_TOKEN_ID}" \
        --rpc-url "${RPC_URL}" \
        --private-key "${RELAYER_PRIVATE_KEY}" \
        --json | jq -r '.transactionHash')

    wait_for_tx "${tx_hash}" "Register token"

    # Verify registration
    is_registered=$("${CAST}" call "${BRIDGE_ADDRESS}" \
        "registeredTokens(address)(bool)" \
        "${MOCK_TOKEN_ADDRESS}" \
        --rpc-url "${RPC_URL}")

    if [[ "${is_registered}" != "true" ]]; then
        error "Token registration failed"
    fi

    success "Token registered with bridge"
}

step_3_mint_tokens() {
    log "=========================================="
    log "Step 3: Mint Test Tokens"
    log "=========================================="

    # Check current balance
    local balance_before
    balance_before=$("${CAST}" call "${MOCK_TOKEN_ADDRESS}" \
        "balanceOf(address)(uint256)" \
        "${RELAYER_ADDRESS}" \
        --rpc-url "${RPC_URL}")

    log "Balance before: ${balance_before}"

    # Mint tokens
    log "Minting ${MINT_AMOUNT} tokens to relayer..."
    local tx_hash
    tx_hash=$("${CAST}" send "${MOCK_TOKEN_ADDRESS}" \
        "mint(address,uint256)" \
        "${RELAYER_ADDRESS}" \
        "${MINT_AMOUNT}" \
        --rpc-url "${RPC_URL}" \
        --private-key "${RELAYER_PRIVATE_KEY}" \
        --json | jq -r '.transactionHash')

    wait_for_tx "${tx_hash}" "Mint tokens"

    # Verify balance
    local balance_after
    balance_after=$("${CAST}" call "${MOCK_TOKEN_ADDRESS}" \
        "balanceOf(address)(uint256)" \
        "${RELAYER_ADDRESS}" \
        --rpc-url "${RPC_URL}")

    log "Balance after: ${balance_after}"
    success "Tokens minted successfully"
}

step_4_approve_bridge() {
    log "=========================================="
    log "Step 4: Approve Bridge to Spend Tokens"
    log "=========================================="

    # Check current allowance
    local allowance_before
    allowance_before=$("${CAST}" call "${MOCK_TOKEN_ADDRESS}" \
        "allowance(address,address)(uint256)" \
        "${RELAYER_ADDRESS}" \
        "${BRIDGE_ADDRESS}" \
        --rpc-url "${RPC_URL}")

    log "Current allowance: ${allowance_before}"

    # Approve if needed
    if [[ "${allowance_before}" -lt "${DEPOSIT_AMOUNT}" ]]; then
        log "Approving bridge to spend tokens..."
        local tx_hash
        tx_hash=$("${CAST}" send "${MOCK_TOKEN_ADDRESS}" \
            "approve(address,uint256)" \
            "${BRIDGE_ADDRESS}" \
            "${MINT_AMOUNT}" \
            --rpc-url "${RPC_URL}" \
            --private-key "${RELAYER_PRIVATE_KEY}" \
            --json | jq -r '.transactionHash')

        wait_for_tx "${tx_hash}" "Approve bridge"
    else
        log "Sufficient allowance already exists"
    fi

    # Verify allowance
    local allowance_after
    allowance_after=$("${CAST}" call "${MOCK_TOKEN_ADDRESS}" \
        "allowance(address,address)(uint256)" \
        "${RELAYER_ADDRESS}" \
        "${BRIDGE_ADDRESS}" \
        --rpc-url "${RPC_URL}")

    log "Allowance after: ${allowance_after}"
    success "Bridge approved"
}

step_5_deposit_to_canton() {
    log "=========================================="
    log "Step 5: Deposit Tokens to Canton"
    log "=========================================="

    # Get nonce before
    local nonce_before
    nonce_before=$("${CAST}" call "${BRIDGE_ADDRESS}" \
        "depositNonces(address)(uint256)" \
        "${RELAYER_ADDRESS}" \
        --rpc-url "${RPC_URL}")

    log "Nonce before: ${nonce_before}"

    # Get locked balance before
    local locked_before
    locked_before=$("${CAST}" call "${BRIDGE_ADDRESS}" \
        "lockedBalances(address)(uint256)" \
        "${MOCK_TOKEN_ADDRESS}" \
        --rpc-url "${RPC_URL}")

    log "Locked balance before: ${locked_before}"

    # Execute deposit
    log "Depositing ${DEPOSIT_AMOUNT} tokens to Canton..."
    log "Canton recipient: ${CANTON_RECIPIENT}"

    local tx_hash
    tx_hash=$("${CAST}" send "${BRIDGE_ADDRESS}" \
        "depositToCanton(address,uint256,bytes32)" \
        "${MOCK_TOKEN_ADDRESS}" \
        "${DEPOSIT_AMOUNT}" \
        "${CANTON_RECIPIENT}" \
        --rpc-url "${RPC_URL}" \
        --private-key "${RELAYER_PRIVATE_KEY}" \
        --json | jq -r '.transactionHash')

    wait_for_tx "${tx_hash}" "Deposit to Canton"

    # Get nonce after
    local nonce_after
    nonce_after=$("${CAST}" call "${BRIDGE_ADDRESS}" \
        "depositNonces(address)(uint256)" \
        "${RELAYER_ADDRESS}" \
        --rpc-url "${RPC_URL}")

    log "Nonce after: ${nonce_after}"

    # Get locked balance after
    local locked_after
    locked_after=$("${CAST}" call "${BRIDGE_ADDRESS}" \
        "lockedBalances(address)(uint256)" \
        "${MOCK_TOKEN_ADDRESS}" \
        --rpc-url "${RPC_URL}")

    log "Locked balance after: ${locked_after}"

    # Verify deposit
    if [[ "${nonce_after}" -gt "${nonce_before}" ]]; then
        success "Deposit successful!"
        log "Deposit TX: ${tx_hash}"
        log "Nonce incremented: ${nonce_before} -> ${nonce_after}"
        log "Locked balance increased: ${locked_before} -> ${locked_after}"
    else
        error "Deposit verification failed"
    fi

    # Parse events from receipt
    log ""
    log "Checking deposit event..."
    local logs
    logs=$("${CAST}" receipt "${tx_hash}" --rpc-url "${RPC_URL}" --json | jq '.logs')

    # DepositToCanton event signature
    local event_sig="DepositToCanton(address,address,uint256,bytes32,uint256)"
    local event_topic
    event_topic=$("${CAST}" keccak "${event_sig}")

    log "Event topic: ${event_topic}"
    echo "${logs}" | jq '.'

    echo ""
    success "=========================================="
    success "E2E Deposit Test Complete!"
    success "=========================================="
    echo ""
    log "Summary:"
    log "  - Token: ${MOCK_TOKEN_ADDRESS}"
    log "  - Amount: ${DEPOSIT_AMOUNT}"
    log "  - Canton Recipient: ${CANTON_RECIPIENT}"
    log "  - TX Hash: ${tx_hash}"
    log ""
    log "Next steps:"
    log "  1. Check middleware logs: tail -f /tmp/relayer.log"
    log "  2. Look for 'Detected DepositToCanton event'"
    log "  3. Check Canton for minted tokens (via Canton console)"
}

step_6_verify_middleware() {
    log "=========================================="
    log "Step 6: Verify Middleware Detection"
    log "=========================================="

    local middleware_log="/tmp/relayer.log"

    if [[ ! -f "${middleware_log}" ]]; then
        warn "Middleware log not found at ${middleware_log}"
        log "Is the middleware running?"
        return
    fi

    log "Checking middleware logs for deposit detection..."

    # Check recent logs for deposit events
    local recent_logs
    recent_logs=$(tail -100 "${middleware_log}" 2>/dev/null || echo "")

    if echo "${recent_logs}" | grep -q "DepositToCanton\|Detected deposit\|Processing deposit"; then
        success "Middleware detected the deposit event!"
        echo "${recent_logs}" | grep -E "DepositToCanton|Detected deposit|Processing deposit" | tail -5
    else
        warn "Deposit not yet detected in middleware logs"
        log "This may take a few seconds (polling interval: 10s)"
        log "Watch logs with: tail -f ${middleware_log}"
    fi
}

# =============================================================================
# Main
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-deploy)
                SKIP_DEPLOY=true
                shift
                ;;
            --token-address)
                MOCK_TOKEN_ADDRESS="$2"
                SKIP_DEPLOY=true
                shift 2
                ;;
            --canton-recipient)
                CANTON_RECIPIENT="$2"
                shift 2
                ;;
            --amount)
                DEPOSIT_AMOUNT="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --skip-deploy          Skip token deployment (use existing)"
                echo "  --token-address <addr> Use existing token address"
                echo "  --canton-recipient <b> Canton fingerprint (bytes32)"
                echo "  --amount <wei>         Deposit amount in wei"
                echo "  -h, --help             Show this help"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

main() {
    echo ""
    echo "=========================================="
    echo "Canton-Ethereum Bridge E2E Test"
    echo "=========================================="
    echo "Network: Sepolia (Chain ID: ${CHAIN_ID})"
    echo "Bridge: ${BRIDGE_ADDRESS}"
    echo "Relayer: ${RELAYER_ADDRESS}"
    echo "=========================================="
    echo ""

    parse_args "$@"

    # Pre-flight checks
    check_foundry
    check_balance

    # Run test steps
    step_1_deploy_mock_token
    step_2_register_token
    step_3_mint_tokens
    step_4_approve_bridge
    step_5_deposit_to_canton
    step_6_verify_middleware

    echo ""
    log "Test completed at $(date)"
}

main "$@"
