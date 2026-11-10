# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Removed
- `docs/E2E-TESTNET-SETUP.md`, `ethereum/scripts/e2e-test.sh` and the `ethereum/web/` demo UI. They targeted an
  older Sepolia test deployment; end-to-end testing now lives in canton-middleware.

### Added
- **EVM Bridge (Solidity)** - `ethereum/` directory:
  - `CantonBridge.sol` - Main bridge contract with deposit/withdraw
  - `TokenRegistry.sol` - Bridgeable token management
  - `RateLimiter.sol` - Per-token rate limiting
  - Foundry test suite
  - Web UI for testing deposits/withdrawals
- **E2E Testing Guide** - `docs/E2E-TESTNET-SETUP.md`:
  - Sepolia testnet deployment instructions
  - Canton quickstart integration
  - Middleware configuration
- **Deployment Scripts**:
  - `scripts/deploy-canton.sh` - DAR deployment helper
  - Updated `build-all.sh` with `--solidity` flag
- Bridge-cBTC package structure (placeholder)
- Bridge-USDC package structure (placeholder)
- Bridge-generic package structure (placeholder)

---

## [2.1.1] - 2026-11-02

Licensing release. The Daml code is unchanged from 2.1.0.

### Changed
- Licensed under the Apache License 2.0: `LICENSE`, `NOTICE` and SPDX headers in all source files (#43)
- All four packages bumped to 2.1.1. The SPDX headers shift the source locations compiled into each
  package, so the package IDs differ from 2.1.0

### Package IDs (Daml SDK 3.4.8)

| Package | Package ID |
|---------|------------|
| `common` | `774bfc61c2fe7d5f472106a2539518a5d4d8093dd90456355783500f330ca1f4` |
| `cip56-token` | `b17adfeb9c93c73cbf914314751ce3a994974b629e5d425dd623775e8e6d35df` |
| `bridge-core` | `baf2d5ef49e7b35f221b489feed3670dcb7e92ed5007587e85282c4027ae5f25` |
| `bridge-wayfinder` | `ab8f35674c9502b3b85a44ddbc61082479327d24269b8eb08e6db44754f8404d` |

---

## [2.1.0] - 2026-06-24

Version bump on `main`, not published as a GitHub release. After the `v2.0.0` tag, `main` kept the
2.0.0 label while the changes below landed, so two different builds called 2.0.0 existed. 2.1.0 gives
the later code its own version; the bump itself changes no source (#45).

### Added
- `TokenTransferEvent` template, mirroring ERC-20 `Transfer(from, to, value)`. Mints, burns and
  transfers all emit it, so an indexer can follow a single template
- `auditObservers` field on `CIP56TransferFactory`

### Changed
- `TokenTransferEvent` is chain-agnostic: the EVM-specific fields (`tokenSymbol`, `eventType`,
  `evmTxHash`, `evmDestination`, `userFingerprint`) are replaced by `instrumentId` and an optional Splice
  `meta`. Bridge callers put chain details in namespaced metadata keys
- `IssuerMint` and `IssuerBurn` return a `TokenTransferEvent` instead of a `MintEvent` or `BurnEvent`,
  and take `eventMeta` instead of individual event parameters

### Removed
- `MintEvent` and `BurnEvent` templates, replaced by `TokenTransferEvent`

### Fixed
- The pre-built Splice API DARs are tracked in git, so the workspace builds from a clean clone

---

## [2.0.0] - 2026-02-24

Tagged as `v2.0.0`, not published as a GitHub release.

### Changed
- CIP-56 contracts rewritten to the Splice token standard (CIP-0056):
  - `CIP56Holding` implements the Splice `HoldingV1.Holding` interface, with `InstrumentId`, `Lock` and
    Splice `Metadata` fields
  - `TokenConfig` carries an `InstrumentId` and Splice `Metadata` instead of `ExtendedMetadata`
  - The Wayfinder bridge's PROMPT metadata (`promptMetadata`) is Splice `Metadata` with
    `splice.chainsafe.io/*` keys, and a `promptInstrumentId` helper is added. `bridge-core` is unchanged

### Added
- `CIP56TransferFactory`, implementing the Splice `TransferFactory` interface for atomic multi-input
  transfers with time validation

### Removed
- `LockedAsset` template and the direct `Transfer`, `Lock`, `Unlock` and `CompleteTransfer` choices,
  replaced by the Splice standard flows

### Fixed
- Transfers carry the first input holding's metadata forward to the receiver and change holdings
  instead of resetting it to empty
- Burning through `CIP56Manager` rejects locked holdings

Releases 1.0.1 to 1.5.0 are described in [GitHub Releases](https://github.com/ChainSafe/canton-erc20/releases).

---

## [1.0.0] - 2025-11-27

### Initial Production Release - Wayfinder Bridge

This release marks the first production-ready deployment of the Canton-EVM Token Bridge, specifically for the **Wayfinder (PROMPT)** token.

### Added

#### Core Infrastructure
- **common** package with shared types:
  - `TokenMeta` - Basic token metadata
  - `ExtendedMetadata` - CIP-56 compliant metadata with ISIN, DTI codes
  - `ChainRef` - Cross-chain event references
  - `EvmAddress` - Ethereum address wrapper
  - `BridgeDirection` - ToCanton/ToEvm direction enum

- **cip56-token** package implementing CIP-56 standard:
  - `CIP56Manager` - Token administration (mint, burn, metadata updates)
  - `CIP56Holding` - Privacy-preserving token holdings
  - `LockedAsset` - Escrow for async transfers
  - `ComplianceRules` - Whitelist/KYC policy management
  - `ComplianceProof` - Individual compliance attestations

- **bridge-core** package with reusable bridge contracts:
  - `MintProposal` - Deposit flow initiation
  - `MintAuthorization` - Dual-signature authorization
  - `RedeemRequest` - Withdrawal flow initiation
  - `BurnEvent` - Middleware notification for EVM release

#### Wayfinder Bridge (Production Ready)
- **bridge-wayfinder** package:
  - `WayfinderBridgeConfig` - Bridge operator configuration
  - `promptMetadata` - PROMPT token metadata (ERC20: `0x28d38df637db75533bd3f71426f3410a82041544`)
  - Full end-to-end test suite (`Wayfinder.Test:testWayfinderBridge`)
  - Comprehensive testing documentation (`TESTING.md`)

#### Privacy & Security
- Need-to-know visibility on all contracts
- No global observers
- Privacy-preserving compliance checks
- Dual-signature authorization for minting

### Security
- All templates validated against Canton privacy best practices
- `CIP56Manager` choices (`Mint`, `Burn`) are `nonconsuming` to prevent state corruption
- Locked asset pattern prevents double-spending during withdrawals

### Documentation
- `TESTING.md` - End-to-end testing guide
- `PHASE_0_QUICKSTART.md` - Getting started guide
- `IMPLEMENTATION_ROADMAP.md` - 18-week implementation plan
- Architecture diagrams and flow charts

---

## Version History

| Version | Date | Milestone |
|---------|------|-----------|
| 2.1.1 | 2026-11-02 | Apache 2.0 licensing |
| 2.1.0 | 2026-06-24 | Own version for the TokenTransferEvent changes |
| 2.0.0 | 2026-02-24 | Splice token standard (CIP-0056) |
| 1.0.1 to 1.5.0 | 2025-12 to 2026-02 | See [GitHub Releases](https://github.com/ChainSafe/canton-erc20/releases) |
| 1.0.0 | 2025-11-27 | Wayfinder PRIME bridge - Production Ready |
| 0.1.0 | 2024-10-XX | Phase 0 Foundation - Multi-package setup |

---

## Migration Guide

### Upgrading to 2.1.x

Smart contract upgrade compatibility, checked with `daml upgrade-check --both` (Daml SDK 3.4.8):

| From | To 2.1.x |
|------|----------|
| 2.1.0 | Upgrades in place |
| 2.0.0 built from `main` from `e44fedc` until the 2.1.0 bump | Upgrades in place |
| `v2.0.0` tag | Not an upgrade: `IssuerMint` changed its return type |
| 1.x (checked against 1.5.0) | Not an upgrade: `LockedAsset` was removed |

Contracts created under an incompatible version can't be used through the 2.1.x packages. Moving them
means archiving and recreating them.

### From Pre-1.0 to 1.0.0

If you were using development versions:

1. **Update `CIP56Manager` usage**: `Mint` and `Burn` choices are now `nonconsuming`
2. **Update withdrawal flow**: Now uses `Lock` → `RedeemRequest` → `ApproveBurn` pattern
3. **Rebuild all packages** in dependency order after pulling changes

```bash
./scripts/clean-all.sh --deep
./scripts/build-all.sh
./scripts/test-all.sh
```

