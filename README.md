# Canton ERC-20 Bridge - Daml Contracts

> **Daml smart contracts for bridging ERC-20 tokens between Ethereum and Canton Network**

[![Daml SDK](https://img.shields.io/badge/Daml%20SDK-3.4.8-blue)](https://docs.daml.com/)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)

This repository contains the Daml implementation of a token bridge connecting ERC-20 tokens on Ethereum with CIP-56 compliant tokens on Canton Network. The Go middleware implementation is maintained in the parent [canton-middleware](https://github.com/ChainSafe/canton-middleware) repository.

## Production Status

| Bridge | Token | Status | Network |
|--------|-------|--------|---------|
| **Wayfinder** | PROMPT | **Production Ready** | 5North DevNet / Mainnet |
| USDC | USDC | In Development | — |
| cBTC | cBTC | In Development | — |
| Generic | Any ERC20 | In Development | — |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        CANTON NETWORK                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │   common    │───>│ cip56-token │───>│ bridge-core │         │
│  │   (types)   │    │  (standard) │    │ (contracts) │         │
│  └─────────────┘    └─────────────┘    └──────┬──────┘         │
│                                               │                 │
│         ┌─────────────────────────────────────┼─────────────┐  │
│         │                    │                │             │  │
│         ▼                    ▼                ▼             ▼  │
│  ┌─────────────┐    ┌─────────────┐   ┌─────────────┐  ┌─────┐│
│  │  wayfinder  │    │    usdc     │   │    cbtc     │  │ ... ││
│  │  (PROMPT)   │    │  (Circle)   │   │  (BitSafe)  │  │     ││
│  │ [PRODUCTION]│    │   [WIP]     │   │    [WIP]    │  │     ││
│  └─────────────┘    └─────────────┘   └─────────────┘  └─────┘│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      GO MIDDLEWARE                              │
│              (Event Streaming + Command Submission)             │
│                    canton-middleware repo                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        ETHEREUM                                 │
│                   (ERC-20 + Bridge Contracts)                   │
│                ethereum-wayfinder submodule                     │
└─────────────────────────────────────────────────────────────────┘
```

## Repository Structure

```
canton-erc20/
├── daml/                               # Daml packages
│   ├── multi-package.yaml              # Workspace configuration
│   │
│   │   # === Core Infrastructure (Production) ===
│   ├── common/                         # Shared types and utilities
│   ├── cip56-token/                    # CIP-56 token standard
│   ├── bridge-core/                    # Core bridge contracts
│   │
│   │   # === Client-Specific Bridges (Production) ===
│   ├── bridge-wayfinder/               # Wayfinder PROMPT (Production)
│   ├── bridge-usdc/                    # USDC (In Development)
│   ├── bridge-cbtc/                    # cBTC (In Development)
│   ├── bridge-generic/                 # Generic ERC20 (In Development)
│   │
│   │   # === Additional Modules (Production) ===
│   ├── dvp/                            # Delivery vs Payment
│   │
│   │   # === Test Packages (with daml-script) ===
│   ├── common-tests/                   # Tests for common
│   ├── cip56-token-tests/              # Tests for cip56-token
│   ├── bridge-core-tests/              # Tests for bridge-core
│   ├── bridge-wayfinder-tests/         # Tests for bridge-wayfinder
│   └── integration-tests/              # End-to-end tests
│
├── docs/                               # Documentation
│   └── DAML_ARCHITECTURE_PROPOSAL.md   # Technical design document
├── CHANGELOG.md                        # Version history
└── README.md                           # This file
```

## Quick Start

### Prerequisites

- **Daml SDK 3.4.8** - [Install Guide](https://docs.daml.com/getting-started/installation.html)

```bash
daml version  # Should show 3.4.8
```

### Build All Packages

From the parent `canton-middleware` repository:

```bash
./scripts/build-dars.sh
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
# Run Wayfinder bridge test
cd daml/bridge-wayfinder-tests
daml script \
  --dar .daml/dist/bridge-wayfinder-tests-1.1.0.dar \
  --script-name Wayfinder.Test:testWayfinderBridge \
  --ide-ledger
```

Expected output:
```
>>> Deposit flow complete: Alice has 1000.0 tokens
>>> Withdrawal initiated: 500.0 tokens pending release on EVM
>>> Withdrawal completed on EVM
✓ Bridge flow test completed successfully!
```

## Package Overview

### Production Packages

These packages are deployed to Canton Network and **do not** include `daml-script` to avoid bloating the package store.

| Package | Description | Status |
|---------|-------------|--------|
| `common` | Shared types (`TokenMeta`, `EvmAddress`, `ChainRef`, `FingerprintAuth`) | Stable |
| `cip56-token` | CIP-56 compliant token with privacy-preserving transfers | Stable |
| `bridge-core` | Issuer-centric bridge contracts (`MintCommand`, `WithdrawalRequest`, `WithdrawalEvent`) | Stable |
| `bridge-wayfinder` | Wayfinder PROMPT token bridge | **Production** |
| `bridge-usdc` | Circle USDC bridge | Development |
| `bridge-cbtc` | BitSafe cBTC bridge | Development |
| `bridge-generic` | Generic ERC20 bridge | Development |
| `dvp` | Delivery vs Payment settlement | Development |

### Test Packages

Test packages include `daml-script` and are **not** deployed to production ledgers.

| Package | Tests |
|---------|-------|
| `common-tests` | `FingerprintAuthTest` |
| `cip56-token-tests` | Mint, Transfer, Compliance flows |
| `bridge-core-tests` | Full bridge cycle |
| `bridge-wayfinder-tests` | E2E Wayfinder flow |
| `integration-tests` | Cross-package integration |

### Package Dependency Graph

```
common                         (no dependencies)
  └── cip56-token             
        └── bridge-core       
              ├── bridge-wayfinder   [PRODUCTION]
              ├── bridge-usdc        [WIP]
              ├── bridge-cbtc        [WIP]
              └── bridge-generic     [WIP]
  └── dvp
```

## Testing

### Test Individual Package

```bash
# CIP-56 Token tests
cd daml/cip56-token-tests
daml script --dar .daml/dist/cip56-token-tests-1.1.0.dar \
  --script-name CIP56.Script:test --ide-ledger

# Bridge Core tests
cd daml/bridge-core-tests
daml script --dar .daml/dist/bridge-core-tests-1.1.0.dar \
  --script-name Bridge.Script:testBridgeFlow --ide-ledger

# Wayfinder tests
cd daml/bridge-wayfinder-tests
daml script --dar .daml/dist/bridge-wayfinder-tests-1.1.0.dar \
  --script-name Wayfinder.Test:testWayfinderBridge --ide-ledger
```

### Test Coverage

| Package | Test Script | Coverage |
|---------|-------------|----------|
| `cip56-token-tests` | `CIP56.Script:test` | Mint, Transfer, Compliance |
| `bridge-core-tests` | `Bridge.Script:testBridgeFlow` | Full bridge cycle |
| `bridge-wayfinder-tests` | `Wayfinder.Test:testWayfinderBridge` | E2E Wayfinder flow |

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
| [Architecture Proposal](docs/DAML_ARCHITECTURE_PROPOSAL.md) | Technical design and roadmap |

## License

[Apache 2.0](LICENSE)

## Support

- **Documentation**: See [docs/](docs/)
- **Issues**: [GitHub Issues](https://github.com/ChainSafe/canton-erc20/issues)

---

