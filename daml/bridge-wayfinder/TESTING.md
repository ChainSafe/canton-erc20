# Wayfinder Bridge - Testing Guide

This document provides a guide to testing the Wayfinder (PROMPT) Bridge Daml smart contracts using the **issuer-centric model**.

## Issuer-Centric Model

In the issuer-centric model:
- **ISSUER** controls all party allocations and bridge operations
- **End users** do NOT manage Canton keys
- **Issuer** mints/burns on behalf of users
- No user "accept" step needed (issuer has full authority)

This model is designed for institutional custody where the issuer (participant node operator) manages all Canton operations on behalf of users who only interact with Ethereum.

## Prerequisites

- **Daml SDK 3.4.8** - [Install Guide](https://docs.daml.com/getting-started/installation.html)
- **Java 17+** (required by Daml runtime)

```bash
daml version  # Should show 3.4.8
```

## Quick Start

### 1. Build All Packages

From the `canton-middleware` repository:

```bash
./scripts/build-dars.sh
```

### 2. Run the End-to-End Test

```bash
cd contracts/canton-erc20/daml/bridge-wayfinder-tests
daml script \
  --dar .daml/dist/bridge-wayfinder-tests-1.0.2.dar \
  --script-name Wayfinder.Test:testWayfinderBridge \
  --ide-ledger
```

## Test Scenarios

### Scenario 1: Deposit (Ethereum → Canton)

**Issuer-Centric Flow:**

```
┌─────────────────┐    ┌──────────────────┐    ┌───────────────────┐
│   Ethereum      │    │     Canton       │    │      User         │
│   (EVM Event)   │    │    (Issuer)      │    │     (Alice)       │
└────────┬────────┘    └────────┬─────────┘    └─────────┬─────────┘
         │                      │                        │
         │  Deposit with        │                        │
         │  fingerprint         │                        │
         │─────────────────────>│                        │
         │                      │                        │
         │                      │  CreatePendingDeposit  │
         │                      │  (from EVM event)      │
         │                      │                        │
         │                      │  ProcessDepositAndMint │
         │                      │───────────────────────>│
         │                      │                        │
         │                      │   CIP56Holding(100.0)  │
         │                      │                        │
```

**Key Points:**
- User deposits on EVM with their Canton fingerprint
- Middleware creates `PendingDeposit` from EVM event
- Issuer resolves fingerprint → Party via `FingerprintMapping`
- Issuer mints directly (no user acceptance needed)

### Scenario 2: Withdrawal (Canton → Ethereum)

**Issuer-Centric Flow:**

```
┌─────────────────┐    ┌──────────────────┐    ┌───────────────────┐
│      User       │    │     Canton       │    │    Ethereum       │
│   (Off-chain)   │    │    (Issuer)      │    │   (EVM Release)   │
└────────┬────────┘    └────────┬─────────┘    └─────────┬─────────┘
         │                      │                        │
         │  Request withdrawal  │                        │
         │  (via API/UI)        │                        │
         │─────────────────────>│                        │
         │                      │                        │
         │                      │  WithdrawalRequest     │
         │                      │  (issuer creates)      │
         │                      │                        │
         │                      │  ProcessWithdrawal     │
         │                      │  (burns tokens)        │
         │                      │                        │
         │                      │  WithdrawalEvent       │
         │                      │───────────────────────>│
         │                      │                        │
         │                      │     Release tokens     │
         │                      │                        │
```

**Key Points:**
- User requests withdrawal off-chain (via API/UI)
- Issuer creates `WithdrawalRequest` on their behalf
- Issuer processes withdrawal (burns tokens, creates event)
- Middleware processes `WithdrawalEvent` → releases on EVM

## Core Contracts

### bridge-core Package

| Template | Purpose |
|----------|---------|
| `MintCommand` | Direct mint by issuer (after fingerprint resolution) |
| `WithdrawalRequest` | Issuer initiates withdrawal for user |
| `WithdrawalEvent` | Event for middleware to release on EVM |

### bridge-wayfinder Package

| Template/Choice | Purpose |
|-----------------|---------|
| `WayfinderBridgeConfig` | Central configuration for the bridge |
| `RegisterUser` | Create fingerprint → Party mapping |
| `CreatePendingDeposit` | Create pending deposit from EVM event |
| `ProcessDepositAndMint` | Resolve fingerprint and mint in one step |
| `InitiateWithdrawal` | Start withdrawal flow for user |
| `DirectMint` | Admin/testing mint (bypasses fingerprint) |

## Running Tests

### Option 1: In-Memory Ledger (Fastest)

```bash
daml script \
  --dar .daml/dist/bridge-wayfinder-tests-1.0.2.dar \
  --script-name Wayfinder.Test:testWayfinderBridge \
  --ide-ledger
```

### Option 2: Against Canton (via test-bridge.sh)

From the `canton-middleware` repository:

```bash
./scripts/test-bridge.sh
```

This starts a full Docker environment with Canton, Anvil, and the relayer.

### Option 3: Using Daml Studio (IDE)

1. Open `daml/bridge-wayfinder-tests/src/Wayfinder/Test.daml` in VS Code
2. Click "Script results" lens above `testWayfinderBridge`
3. View transaction tree and contract states interactively

## Troubleshooting

### Error: `ContractNotActive`

**Cause:** A contract was archived before being used.

**Solution:** Ensure contracts are used in the correct order:
- Don't use a `CIP56Holding` after it was transferred
- `CIP56Manager` uses nonconsuming choices so it persists

### Error: `ContractNotVisible`

**Cause:** A party is trying to access a contract they cannot see.

**Solution:** Check `signatory` and `observer` declarations. Ensure the party is either:
- A signatory of the contract
- An observer of the contract

### Error: Package not found

**Cause:** DARs not built or wrong version.

**Solution:**
```bash
./scripts/build-dars.sh
```

## Summary

| Test | Location | What it Validates |
|------|----------|-------------------|
| Wayfinder E2E | `bridge-wayfinder-tests` | Full deposit/withdrawal lifecycle |
| Bridge Core | `bridge-core-tests` | Core issuer-centric contracts |
| CIP-56 Token | `cip56-token-tests` | Token minting, transfer, compliance |
