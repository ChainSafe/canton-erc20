# Canton EVM Bridge - Solidity Contracts

Solidity smart contracts for the EVM side of the Canton Network bridge.

## Overview

These contracts enable bidirectional token transfers between EVM chains (Ethereum, Base, etc.) and Canton Network:

- **Deposits (EVM → Canton)**: Users lock ERC-20 tokens in the bridge contract. The middleware detects the deposit event and mints CIP-56 tokens on Canton.
- **Withdrawals (Canton → EVM)**: Canton burns CIP-56 tokens. The middleware signs a withdrawal proof, and the relayer releases ERC-20 tokens on EVM.

## Contracts

### Core

| Contract | Description |
|----------|-------------|
| `CantonBridge.sol` | Main bridge contract with deposit/withdraw functionality |
| `TokenRegistry.sol` | Registry for managing bridgeable ERC-20 tokens |

### Interfaces

| Interface | Description |
|-----------|-------------|
| `ICantonBridge.sol` | Bridge interface with events and errors |
| `IBridgeEvents.sol` | Administrative and operational events |

### Security

| Contract | Description |
|----------|-------------|
| `RateLimiter.sol` | Rate limiting per token per time period |

### Mocks

| Contract | Description |
|----------|-------------|
| `MockERC20.sol` | Mock tokens for testing (USDC, WBTC, PROMPT) |

## Key Features

- **Role-Based Access Control**: Admin, Relayer, and Pauser roles
- **Rate Limiting**: Configurable per-token rate limits
- **Reentrancy Protection**: All state-changing functions protected
- **Pausable**: Emergency pause functionality
- **Large Withdrawal Time Lock**: Configurable delay for large withdrawals
- **Signature Verification**: Withdrawals require valid relayer signature

## Build

```bash
# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test -vv
```

## Deployment

```bash
# Set environment variables
export PRIVATE_KEY=<deployer-private-key>
export ADMIN_ADDRESS=<admin-address>
export RELAYER_ADDRESS=<relayer-address>

# Deploy to network
forge script script/Deploy.s.sol --rpc-url <rpc-url> --broadcast
```

## Usage

### Deposit (EVM → Canton)

```solidity
// 1. Approve tokens
IERC20(token).approve(bridgeAddress, amount);

// 2. Deposit with Canton fingerprint
bridge.depositToCanton(token, amount, cantonRecipient);
```

### Withdrawal (Canton → EVM)

Called by the relayer after Canton burn is confirmed:

```solidity
// Relayer signs the withdrawal message
bridge.withdrawFromCanton(token, amount, recipient, withdrawalId, proof);
```

## Security Considerations

- Only registered tokens can be bridged
- Withdrawals require valid signature from authorized relayer
- Rate limits prevent drain attacks
- Large withdrawals are time-locked
- Emergency pause available for incidents

## Events

### Deposit Events
- `DepositToCanton(token, sender, amount, cantonRecipient, nonce)`

### Withdrawal Events
- `WithdrawalFromCanton(token, recipient, amount, cantonSender, withdrawalId)`
- `WithdrawalProcessed(withdrawalId, success)`

### Admin Events
- `TokenRegistered(token, symbol, cantonTokenId, isNative)`
- `BridgePaused(by)` / `BridgeUnpaused(by)`
- `RateLimitSet(token, amount, period)`

## License

Apache 2.0
