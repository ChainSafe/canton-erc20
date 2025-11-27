# Canton ERC-20 Bridge - DAML Contracts

> **DAML smart contracts for bridging ERC-20 tokens between Ethereum and Canton Network**

[![DAML SDK](https://img.shields.io/badge/DAML%20SDK-2.10.2-blue)](https://docs.daml.com/)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)

This repository contains the DAML implementation of a token bridge connecting ERC-20 tokens on Ethereum with CIP-56 compliant tokens on Canton Network. The Go middleware implementation is maintained separately.

## 🚀 Production Status

| Bridge | Token | Status | Documentation |
|--------|-------|--------|---------------|
| **Wayfinder** | PRIME (`0x28d38...1544`) | ✅ **Production Ready** | [Testing Guide](daml/bridge-wayfinder/TESTING.md) |
| USDC | USDC | 🚧 In Development | [Requirements](docs/sow/usdc.md) |
| cBTC | cBTC | 🚧 In Development | [Requirements](docs/sow/cbtc.md) |
| Generic | Any ERC20 | 🚧 In Development | [Requirements](docs/sow/evm.md) |

## 🏗️ Architecture

This is a **multi-package DAML workspace** implementing:

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
│  │   (PRIME)   │    │  (Circle)   │   │  (BitSafe)  │  │     ││
│  │     ✅      │    │     🚧      │   │     🚧      │  │     ││
│  └─────────────┘    └─────────────┘   └─────────────┘  └─────┘│
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      GO MIDDLEWARE                              │
│              (Event Streaming + Command Submission)             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        ETHEREUM                                 │
│                    (ERC-20 Contracts)                           │
└─────────────────────────────────────────────────────────────────┘
```

## 📦 Repository Structure

```
canton-erc20/
├── daml/                           # DAML packages
│   ├── multi-package.yaml          # Workspace configuration
│   │
│   │   # === Core Infrastructure ===
│   ├── common/                     # Shared types and utilities
│   ├── cip56-token/                # CIP-56 token standard
│   ├── bridge-core/                # Core bridge contracts
│   │
│   │   # === Client-Specific Bridges ===
│   ├── bridge-wayfinder/           # ✅ Wayfinder PRIME (Production)
│   ├── bridge-usdc/                # 🚧 USDC (In Development)
│   ├── bridge-cbtc/                # 🚧 cBTC (In Development)
│   ├── bridge-generic/             # 🚧 Generic ERC20 (In Development)
│   │
│   │   # === Additional Modules ===
│   ├── dvp/                        # Delivery vs Payment
│   └── integration-tests/          # End-to-end tests
│
├── docs/                           # Documentation
├── scripts/                        # Build and test scripts
├── CHANGELOG.md                    # Version history
└── README.md                       # This file
```

## 🚀 Quick Start

### Prerequisites

- **DAML SDK 2.10.2** - [Install Guide](https://docs.daml.com/getting-started/installation.html)

```bash
daml version  # Should show 2.10.2
```

### Build All Packages

```bash
./scripts/build-all.sh
```

### Run Wayfinder Bridge Tests

```bash
cd daml/bridge-wayfinder
daml script \
  --dar .daml/dist/bridge-wayfinder-1.0.0.dar \
  --script-name Wayfinder.Test:testWayfinderBridge \
  --ide-ledger
```

Expected output:
```
>>> 1. Initialization: Deploying contracts...
    ✓ Token Manager and Bridge Config deployed.
>>> 2. Deposit Flow: Bridging 100.0 PRIME from Ethereum to Alice...
    ✓ Deposit complete. Alice holds 100.0 PRIME.
>>> 3. Native Transfer: Alice transfers 40.0 PRIME to Bob...
    ✓ Transfer successful.
>>> 4. Withdrawal Flow: Bob bridges 40.0 PRIME back to Ethereum...
    ✓ Redemption processed on Canton.
>>> 5. Final Verification...
    ✓ BurnEvent confirmed correct.
>>> Test Cycle Complete Successfully!
```

## 📋 Package Overview

### Core Infrastructure

| Package | Description | Status |
|---------|-------------|--------|
| `common` | Shared types (`TokenMeta`, `EvmAddress`, `ChainRef`) | ✅ Stable |
| `cip56-token` | CIP-56 compliant token with privacy-preserving transfers | ✅ Stable |
| `bridge-core` | Reusable bridge contracts (`MintProposal`, `RedeemRequest`, `BurnEvent`) | ✅ Stable |

### Client Bridges

| Package | Token | EVM Contract | Status |
|---------|-------|--------------|--------|
| `bridge-wayfinder` | PRIME | `0x28d38df637db75533bd3f71426f3410a82041544` | ✅ Production |
| `bridge-usdc` | USDC | TBD | 🚧 Development |
| `bridge-cbtc` | cBTC | TBD | 🚧 Development |
| `bridge-generic` | Any ERC20 | Dynamic | 🚧 Development |

## 🔒 Security & Privacy

All contracts implement Canton privacy best practices:

- ✅ **Need-to-Know Visibility** - Contracts visible only to relevant parties
- ✅ **No Global Observers** - No admin parties that see all transactions
- ✅ **Privacy-Preserving Compliance** - Whitelist checks without leaking user lists
- ✅ **Dual-Signature Authorization** - Multi-party consent for minting
- ✅ **Locked Asset Pattern** - Prevents double-spending during withdrawals

## 🧪 Testing

### Run All Tests

```bash
./scripts/test-all.sh
```

### Test Specific Package

```bash
cd daml/bridge-wayfinder
daml script --dar .daml/dist/bridge-wayfinder-1.0.0.dar \
  --script-name Wayfinder.Test:testWayfinderBridge --ide-ledger
```

### Test Coverage

| Package | Test Script | Coverage |
|---------|-------------|----------|
| `cip56-token` | `CIP56.Script:test` | Mint, Transfer, Compliance |
| `bridge-core` | `Bridge.Script:testBridgeFlow` | Full bridge cycle |
| `bridge-wayfinder` | `Wayfinder.Test:testWayfinderBridge` | E2E Wayfinder flow |

## 🔧 Development

### Adding a New Client Bridge

1. Create package directory:
   ```bash
   mkdir -p daml/bridge-mytoken/src/MyToken
   ```

2. Create `daml.yaml`:
   ```yaml
   name: bridge-mytoken
   version: 1.0.0
   sdk-version: 2.10.2
   source: src
   dependencies:
     - daml-prim
     - daml-stdlib
     - daml-script
   data-dependencies:
     - ../common/.daml/dist/common-1.0.0.dar
     - ../cip56-token/.daml/dist/cip56-token-1.0.0.dar
     - ../bridge-core/.daml/dist/bridge-core-1.0.0.dar
   ```

3. Implement bridge module (use `bridge-wayfinder` as template)

4. Add to `multi-package.yaml`

5. Build and test:
   ```bash
   ./scripts/build-all.sh
   ./scripts/test-all.sh
   ```

### Package Dependency Order

```
1. common              (no dependencies)
2. cip56-token         (depends on common)
3. bridge-core         (depends on common, cip56-token)
4. bridge-wayfinder    (depends on bridge-core)
   bridge-usdc         (depends on bridge-core)
   bridge-cbtc         (depends on bridge-core)
   bridge-generic      (depends on bridge-core)
5. dvp                 (depends on common)
6. integration-tests   (depends on all packages)
```

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [CHANGELOG.md](CHANGELOG.md) | Version history and migration guides |
| [Wayfinder Testing Guide](daml/bridge-wayfinder/TESTING.md) | End-to-end testing walkthrough |
| [Phase 0 Quickstart](docs/PHASE_0_QUICKSTART.md) | Getting started guide |
| [Implementation Roadmap](docs/IMPLEMENTATION_ROADMAP.md) | 18-week implementation plan |
| [Architecture Proposal](docs/DAML_ARCHITECTURE_PROPOSAL.md) | Technical design document |

## 🤝 Contributing

### Branching Strategy

```
main                    # Production-ready code
├── develop             # Integration branch
│   ├── feature/usdc-bridge
│   ├── feature/cbtc-bridge
│   └── feature/generic-bridge
└── release/v1.0.0      # Release branches
```

### Commit Convention

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(wayfinder): add full bridge lifecycle test
fix(cip56): make Manager choices nonconsuming
docs(readme): update production status
chore(deps): bump DAML SDK to 2.10.2
```

## 📄 License

[Apache 2.0](LICENSE)

## 🙋 Support

- **Documentation**: See [docs/](docs/)
- **Issues**: [GitHub Issues](https://github.com/your-org/canton-erc20/issues)

---

**Built with ❤️ using DAML and Canton Network**
