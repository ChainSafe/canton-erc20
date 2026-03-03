# Canton ERC-20 Bridge - Daml Contracts

> **Daml smart contracts for bridging ERC-20 tokens between Ethereum and Canton Network**

[![Daml SDK](https://img.shields.io/badge/Daml%20SDK-3.4.8-blue)](https://docs.daml.com/)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)

This repository contains the Daml implementation of a token bridge connecting ERC-20 tokens on Ethereum with CIP-56 compliant tokens on Canton Network. The Go middleware implementation is maintained in the parent [canton-middleware](https://github.com/ChainSafe/canton-middleware) repository.

## Architecture

```
                         CANTON NETWORK
+---------------------------------------------------------------+
|                                                                 |
|  +-----------+    +------------+    +------------+              |
|  |  common   |--->| cip56-token|--->| bridge-core|              |
|  |  (types)  |    | (standard) |    | (contracts)|              |
|  +-----------+    +------------+    +------+-----+              |
|                                           |                     |
|                                           v                     |
|                                    +--------------+             |
|                                    |  wayfinder   |             |
|                                    |  (PROMPT)    |             |
|                                    +--------------+             |
|                                                                 |
+-----------------------------------------------------------------+
                              |
                              v
+-----------------------------------------------------------------+
|                      GO MIDDLEWARE                               |
|              (Event Streaming + Command Submission)              |
|                    canton-middleware repo                        |
+-----------------------------------------------------------------+
                              |
                              v
+-----------------------------------------------------------------+
|                        ETHEREUM                                 |
|                   (ERC-20 + Bridge Contracts)                   |
|                ethereum-wayfinder submodule                     |
+-----------------------------------------------------------------+
```

## Repository Structure

```
canton-erc20/
├── daml/                               # Daml packages
│   ├── multi-package.yaml              # Workspace configuration
│   │
│   │   # === Core Infrastructure ===
│   ├── common/                         # Shared types and utilities
│   ├── cip56-token/                    # CIP-56 token standard + unified TokenConfig + Events
│   ├── bridge-core/                    # Core bridge contracts (MintCommand, WithdrawalRequest)
│   │
│   │   # === Bridge ===
│   ├── bridge-wayfinder/               # Wayfinder PROMPT token bridge
│   │
│   │   # === Test Packages (with daml-script) ===
│   ├── common-tests/                   # Tests for common
│   ├── cip56-token-tests/              # Tests for CIP-56 token + TokenConfig
│   ├── bridge-core-tests/              # Tests for bridge-core
│   ├── bridge-wayfinder-tests/         # Tests for bridge-wayfinder
│   └── integration-tests/              # Cross-package integration
│
├── ethereum/                           # EVM Bridge (Solidity)
│   ├── contracts/                      # Solidity smart contracts
│   │   ├── CantonBridge.sol            # Main bridge contract
│   │   └── TokenRegistry.sol          # Token registration
│   ├── script/                         # Foundry deployment scripts
│   ├── test/                           # Solidity tests
│   └── web/                            # Bridge web UI
│
├── docs/                               # Documentation
│   ├── E2E-TESTNET-SETUP.md            # End-to-end testing guide
│   └── DAML_ARCHITECTURE_PROPOSAL.md   # Technical design document
├── CHANGELOG.md                        # Version history
└── README.md                           # This file
```

## Quick Start

### Prerequisites

- **Daml SDK 3.4.8** - [Install Guide](https://docs.daml.com/getting-started/installation.html)
- **Go 1.21+** - For middleware (optional, for E2E testing)
- **Foundry** - For Solidity contracts (optional, for E2E testing)

```bash
daml version  # Should show 3.4.8
```

### Build All Packages

From the parent `canton-middleware` repository:

```bash
./scripts/setup/build-dars.sh
```

Or build individually from this directory:

```bash
cd daml/common && daml build --no-legacy-assistant-warning
cd ../cip56-token && daml build --no-legacy-assistant-warning
cd ../bridge-core && daml build --no-legacy-assistant-warning
cd ../bridge-wayfinder && daml build --no-legacy-assistant-warning
```

### Run Tests

```bash
# Run all DAML tests
./scripts/test-all.sh --verbose

# Or run individual test packages
cd daml/cip56-token-tests && daml test
cd daml/bridge-core-tests && daml test
cd daml/bridge-wayfinder-tests && daml test
```

## Package Overview

### Production Packages

These packages are deployed to Canton Network and **do not** include `daml-script` to avoid bloating the package store.

| Package | Description | Status |
|---------|-------------|--------|
| `common` | Shared types (`TokenMeta`, `EvmAddress`, `ChainRef`, `FingerprintAuth`) | Stable |
| `cip56-token` | CIP-56 compliant token, unified `TokenConfig`, `TokenTransferEvent`, `CIP56TransferFactory` | Stable |
| `bridge-core` | Issuer-centric bridge contracts (`MintCommand`, `WithdrawalRequest`, `WithdrawalEvent`) | Stable |
| `bridge-wayfinder` | Wayfinder PROMPT token bridge (thin EVM layer delegating to `TokenConfig`) | **Production** |

### Test Packages

Test packages include `daml-script` and are **not** deployed to production ledgers.

| Package | Tests |
|---------|-------|
| `common-tests` | `FingerprintAuthTest` |
| `cip56-token-tests` | Mint, burn, transfer (single/multi-input/exact), lock, interface, TokenTransferEvent |
| `bridge-core-tests` | Full bridge cycle, partial burns |
| `bridge-wayfinder-tests` | Full cycle, issuer-centric flow, fingerprint validation, multi-user |
| `integration-tests` | Cross-package integration |

### Package Dependency Graph

```
common                         (no dependencies)
  └── cip56-token
        └── bridge-core
              └── bridge-wayfinder
```

## Unified Token Architecture

All tokens -- whether native Canton tokens or EVM-bridged -- share the same core logic:

```
TokenConfig (CIP56.Config)
├── IssuerMint  --> CIP56Manager.Mint + TokenTransferEvent (MINT)
└── IssuerBurn  --> CIP56Manager.Burn + TokenTransferEvent (BURN)

CIP56TransferFactory (CIP56.TransferFactory)
└── Transfer    --> Archive inputs + Create holdings + TokenTransferEvent (TRANSFER)
```

- **`TokenTransferEvent`** is a unified audit event emitted from all three token mutation points (mint, burn, transfer). It mirrors ERC-20's `Transfer(from, to, value)` pattern with `Optional Party` fields: `fromParty = None` for mints, `toParty = None` for burns, both set for transfers. Bridge-specific fields (`evmTxHash`, `evmDestination`, `userFingerprint`) are `Optional` -- set only for bridge mints/burns. The indexer subscribes to this single template for a complete event stream.
- **`TokenConfig`** holds a `CIP56Manager` reference and token metadata. Every mint produces a `CIP56Holding` and a `TokenTransferEvent`; every burn produces a `TokenTransferEvent`. Optional fields (`evmTxHash`, `evmDestination`) distinguish native operations from bridge operations.
- **`CIP56TransferFactory`** implements the Splice `TransferFactory` interface for peer-to-peer transfers. It archives sender input holdings, creates receiver and change holdings, and emits a `TokenTransferEvent` with `eventType = "TRANSFER"`.
- **`WayfinderBridgeConfig`** is a thin EVM layer. It holds a `tokenConfigCid` reference and delegates all minting and burning to `TokenConfig`. The bridge itself only handles EVM-specific concerns: fingerprint registration, deposit validation, and withdrawal initiation.

To add a new bridged token (e.g. USDC), create:
1. A new `TokenConfig` instance with its own `CIP56Manager` and metadata
2. A new bridge config module that holds a reference to that `TokenConfig`

The core mint/burn/event logic is identical for every token. The bridge is just an optional EVM entry point.

## Testing

### Test Individual Package

```bash
# CIP-56 Token tests (mint, transfer with merge, compliance)
cd daml/cip56-token-tests && daml test

# Bridge Core tests (full bridge cycle, audit events)
cd daml/bridge-core-tests && daml test

# Wayfinder tests (E2E deposit/withdrawal flow)
cd daml/bridge-wayfinder-tests && daml test
```

### Test Coverage

| Package | Tests | Coverage |
|---------|-------|----------|
| `cip56-token-tests` | `testMintAndBurn`, `testTransferViaFactory`, `testTransferMultipleInputs`, `testTransferExactAmount`, `testBurnLockedHoldingFails`, `testHoldingInterface`, `testTokenTransferEvents` | Mint, burn, transfer (single/multi-input/exact), locked holding rejection, Holding interface, unified TokenTransferEvent for all 3 paths |
| `bridge-wayfinder-tests` | `testFullCycle`, `testIssuerCentricBridge`, `testFingerprintMismatchRejected`, `testMultipleUsers` | Full bridge cycle, issuer-centric flow, fingerprint validation, multi-user |

## EVM Bridge

The `ethereum/` directory contains the Solidity smart contracts for the EVM side of the bridge:

| Contract | Description |
|----------|-------------|
| `CantonBridge.sol` | Main bridge contract with deposit/withdraw |
| `TokenRegistry.sol` | Registry for bridgeable ERC-20 tokens |

See [ethereum/README.md](ethereum/README.md) for contract details.

## E2E Testing

For full end-to-end testing with Ethereum integration, see:

**[docs/E2E-TESTNET-SETUP.md](docs/E2E-TESTNET-SETUP.md)** - Complete guide covering:
- Canton Network quickstart setup
- EVM contract deployment (Sepolia)
- Middleware configuration
- Deposit/withdrawal testing
- Troubleshooting

## Security & Privacy

All contracts implement Canton privacy best practices:

- **Need-to-Know Visibility** - Contracts visible only to relevant parties
- **No Global Observers** - No admin parties that see all transactions
- **Privacy-Preserving Compliance** - Whitelist checks without leaking user lists
- **Issuer-Centric Model** - Issuer controls minting/burning on behalf of users (no user Canton keys required)
- **Fingerprint-Based Authentication** - EVM addresses map to Canton parties via cryptographic fingerprints

## Documentation

| Document | Description |
|----------|-------------|
| [CHANGELOG.md](CHANGELOG.md) | Version history and migration guides |
| [E2E Testnet Setup](docs/E2E-TESTNET-SETUP.md) | Full end-to-end testing guide |
| [Architecture Proposal](docs/DAML_ARCHITECTURE_PROPOSAL.md) | Technical design and roadmap |
| [EVM Bridge](ethereum/README.md) | Solidity contracts documentation |

## License

[Apache 2.0](LICENSE)

## Support

- **Documentation**: See [docs/](docs/)
- **Issues**: [GitHub Issues](https://github.com/ChainSafe/canton-erc20/issues)

---
