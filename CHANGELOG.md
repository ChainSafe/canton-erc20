# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Bridge-cBTC package structure (placeholder)
- Bridge-USDC package structure (placeholder)
- Bridge-generic package structure (placeholder)

---

## [1.0.0] - 2024-11-27

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
| 1.0.0 | 2024-11-27 | Wayfinder PRIME bridge - Production Ready |
| 0.1.0 | 2024-10-XX | Phase 0 Foundation - Multi-package setup |

---

## Upcoming Releases

### [1.1.0] - Planned
- USDC Bridge (Circle xReserve integration)
- Enhanced compliance rules

### [1.2.0] - Planned
- cBTC Bridge (BitSafe vault integration)
- Multi-sig support

### [1.3.0] - Planned
- Generic ERC20 Bridge
- Dynamic token registration

### [2.0.0] - Planned
- DvP Settlement integration
- Cross-asset atomic swaps

---

## Migration Guide

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

