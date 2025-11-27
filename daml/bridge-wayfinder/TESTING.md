# Wayfinder Bridge - End-to-End Testing Guide

This document provides a comprehensive guide to testing the Wayfinder (PRIME) Bridge DAML smart contracts.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Project Structure](#project-structure)
3. [Quick Start](#quick-start)
4. [Test Scenarios](#test-scenarios)
5. [Running Tests](#running-tests)
6. [Understanding the Test Flow](#understanding-the-test-flow)
7. [Troubleshooting](#troubleshooting)
8. [Advanced Testing](#advanced-testing)

---

## Prerequisites

### Required Software

- **DAML SDK** (version 2.10.2 or compatible)
- **Java 17+** (required by DAML runtime)

### Verify Installation

```bash
daml version
# Expected: SDK versions: 2.10.2

java -version
# Expected: openjdk version "17.x.x" or higher
```

---

## Project Structure

```
daml/
├── common/                    # Shared types (TokenMeta, EvmAddress, etc.)
├── cip56-token/              # CIP-56 compliant token implementation
│   └── src/CIP56/
│       ├── Token.daml        # CIP56Manager, CIP56Holding, LockedAsset
│       └── Compliance.daml   # ComplianceRules, ComplianceProof
├── bridge-core/              # Core bridge contracts
│   └── src/Bridge/
│       └── Contracts.daml    # MintProposal, RedeemRequest, BurnEvent
└── bridge-wayfinder/         # Wayfinder-specific bridge
    └── src/Wayfinder/
        ├── Bridge.daml       # WayfinderBridgeConfig, primeMetadata
        └── Test.daml         # End-to-end test script
```

---

## Quick Start

### 1. Build All Packages (in dependency order)

```bash
cd daml

# Build common types
cd common && daml build --enable-multi-package=no && cd ..

# Build CIP-56 token
cd cip56-token && daml build --enable-multi-package=no && cd ..

# Build bridge core
cd bridge-core && daml build --enable-multi-package=no && cd ..

# Build Wayfinder bridge
cd bridge-wayfinder && daml build --enable-multi-package=no && cd ..
```

### 2. Run the End-to-End Test

```bash
cd bridge-wayfinder
daml script \
  --dar .daml/dist/bridge-wayfinder-1.0.0.dar \
  --script-name Wayfinder.Test:testWayfinderBridge \
  --ide-ledger
```

### Expected Output

```
[DA.Internal.Prelude:557]: ">>> 1. Initialization: Deploying contracts..."
[DA.Internal.Prelude:557]: "    ✓ Token Manager and Bridge Config deployed."
[DA.Internal.Prelude:557]: ">>> 2. Deposit Flow: Bridging 100.0 PRIME from Ethereum to Alice..."
[DA.Internal.Prelude:557]: "    ✓ Deposit complete. Alice holds 100.0 PRIME."
[DA.Internal.Prelude:557]: ">>> 3. Native Transfer: Alice transfers 40.0 PRIME to Bob..."
[DA.Internal.Prelude:557]: "    ✓ Transfer successful."
[DA.Internal.Prelude:557]: ">>> 4. Withdrawal Flow: Bob bridges 40.0 PRIME back to Ethereum..."
[DA.Internal.Prelude:557]: "    ✓ Redemption processed on Canton."
[DA.Internal.Prelude:557]: ">>> 5. Final Verification..."
[DA.Internal.Prelude:557]: "    ✓ BurnEvent confirmed correct."
[DA.Internal.Prelude:557]: ">>> Test Cycle Complete Successfully!"
```

---

## Test Scenarios

### Scenario 1: Deposit (Ethereum → Canton)

**What it tests:** Bridging tokens from Ethereum to Canton

**Flow:**
```
┌─────────────────┐    ┌──────────────────┐    ┌───────────────────┐
│   Ethereum      │    │     Canton       │    │      User         │
│   (Simulated)   │    │   (Operator)     │    │     (Alice)       │
└────────┬────────┘    └────────┬─────────┘    └─────────┬─────────┘
         │                      │                        │
         │  Lock PRIME on EVM   │                        │
         │─────────────────────>│                        │
         │                      │                        │
         │                      │  CreateMintProposal    │
         │                      │───────────────────────>│
         │                      │                        │
         │                      │       Accept           │
         │                      │<───────────────────────│
         │                      │                        │
         │                      │     MintOnCanton       │
         │                      │───────────────────────>│
         │                      │                        │
         │                      │   CIP56Holding(100.0)  │
         │                      │                        │
```

**Test Code:**
```daml
-- Step 1: Operator creates mint proposal
proposalCid <- submit operator do
  exerciseCmd configCid CreateMintProposal with
    recipient = alice
    amount = 100.0
    txHash = "0x1234567890abcdef..."

-- Step 2: Alice accepts
authCid <- submit alice do
  exerciseCmd proposalCid Accept

-- Step 3: Operator mints
holdingCid <- submit operator do
  exerciseCmd authCid MintOnCanton
```

---

### Scenario 2: Native Transfer (Canton)

**What it tests:** Standard CIP-56 token transfer between users

**Flow:**
```
┌─────────────────┐                      ┌─────────────────┐
│     Alice       │                      │       Bob       │
│  (100.0 PRIME)  │                      │   (0.0 PRIME)   │
└────────┬────────┘                      └────────┬────────┘
         │                                        │
         │  Transfer 40.0 PRIME                   │
         │───────────────────────────────────────>│
         │                                        │
         │  Change: 60.0 PRIME                    │  Received: 40.0 PRIME
         │                                        │
```

**Test Code:**
```daml
(bobHoldingCid, maybeChangeCid) <- submit alice do
  exerciseCmd aliceHoldingCid Transfer with
    to = bob
    value = 40.0
    complianceRulesCid = None
    complianceProofCid = None
```

---

### Scenario 3: Withdrawal (Canton → Ethereum)

**What it tests:** Bridging tokens from Canton back to Ethereum

**Flow:**
```
┌─────────────────┐    ┌──────────────────┐    ┌───────────────────┐
│      Bob        │    │     Canton       │    │    Ethereum       │
│  (40.0 PRIME)   │    │   (Operator)     │    │   (Simulated)     │
└────────┬────────┘    └────────┬─────────┘    └─────────┬─────────┘
         │                      │                        │
         │  Lock funds          │                        │
         │─────────────────────>│                        │
         │                      │                        │
         │  Create RedeemRequest│                        │
         │─────────────────────>│                        │
         │                      │                        │
         │                      │  ApproveBurn           │
         │                      │───────────────────────>│
         │                      │                        │
         │                      │  BurnEvent emitted     │
         │                      │  (Middleware listens)  │
         │                      │                        │
         │                      │     Unlock on EVM      │
         │                      │───────────────────────>│
```

**Test Code:**
```daml
-- Step 1: Bob locks funds for operator
(lockedAssetCid, _) <- submit bob do
  exerciseCmd bobHoldingCid Lock with
    receiver = operator
    value = 40.0
    complianceRulesCid = None

-- Step 2: Bob creates redeem request
redeemRequestCid <- submit bob do
  createCmd RedeemRequest with
    owner = bob
    operator = operator
    issuer = operator
    tokenManagerCid = tokenManagerCid
    lockedAssetCid = lockedAssetCid
    amount = 40.0
    destination = EvmAddress "0xBobEthAddress..."
    reference = "req-001"

-- Step 3: Operator approves burn
burnEventCid <- submit operator do
  exerciseCmd redeemRequestCid ApproveBurn
```

---

## Running Tests

### Option 1: In-Memory Ledger (Fastest)

```bash
daml script \
  --dar .daml/dist/bridge-wayfinder-1.0.0.dar \
  --script-name Wayfinder.Test:testWayfinderBridge \
  --ide-ledger
```

### Option 2: Against a Running Canton Node

```bash
# Start Canton sandbox in another terminal
daml sandbox

# Run test against sandbox
daml script \
  --dar .daml/dist/bridge-wayfinder-1.0.0.dar \
  --script-name Wayfinder.Test:testWayfinderBridge \
  --ledger-host localhost \
  --ledger-port 6865
```

### Option 3: Using DAML Studio (IDE)

1. Open `daml/bridge-wayfinder/src/Wayfinder/Test.daml` in VS Code with DAML extension
2. Click "Script results" lens above `testWayfinderBridge`
3. View transaction tree and contract states interactively

---

## Understanding the Test Flow

### Contract Lifecycle

```
┌───────────────────────────────────────────────────────────────────┐
│                        INITIALIZATION                             │
├───────────────────────────────────────────────────────────────────┤
│  CIP56Manager (created) ────────────────────────────────────────> │
│  WayfinderBridgeConfig (created) ───────────────────────────────> │
└───────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────────┐
│                        DEPOSIT FLOW                               │
├───────────────────────────────────────────────────────────────────┤
│  MintProposal (created) ──> MintAuthorization (created) ──>       │
│  CIP56Holding[Alice, 100.0] (created)                             │
└───────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────────┐
│                        TRANSFER FLOW                              │
├───────────────────────────────────────────────────────────────────┤
│  CIP56Holding[Alice, 100.0] (archived) ──>                        │
│  CIP56Holding[Bob, 40.0] (created) +                              │
│  CIP56Holding[Alice, 60.0] (created)                              │
└───────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────────┐
│                        WITHDRAWAL FLOW                            │
├───────────────────────────────────────────────────────────────────┤
│  CIP56Holding[Bob, 40.0] (archived) ──>                           │
│  LockedAsset[Bob→Operator, 40.0] (created) ──>                    │
│  RedeemRequest (created) ──>                                      │
│  LockedAsset (archived) + CIP56Holding (archived) ──>             │
│  BurnEvent (created)                                              │
└───────────────────────────────────────────────────────────────────┘
```

### Key Assertions

| Step | Assertion | Purpose |
|------|-----------|---------|
| Deposit | `aliceHolding.amount == 100.0` | Verify correct mint amount |
| Deposit | `aliceHolding.meta.symbol == "PRIME"` | Verify token metadata |
| Transfer | `bobHolding.amount == 40.0` | Verify transfer amount |
| Transfer | `change.amount == 60.0` | Verify change returned |
| Withdrawal | `burnEvent.amount == 40.0` | Verify burn amount |
| Withdrawal | `burnEvent.destination == evmDest` | Verify EVM destination |

---

## Troubleshooting

### Error: `ContractNotActive`

**Cause:** A contract was archived before being used.

**Solution:** Ensure contracts are used in the correct order. Common issues:
- Using a `CIP56Holding` after it was transferred
- Using `CIP56Manager` after it was consumed (fixed by making `Mint`/`Burn` nonconsuming)

### Error: `ContractNotVisible`

**Cause:** A party is trying to access a contract they cannot see.

**Solution:** Check `signatory` and `observer` declarations. Ensure the party is either:
- A signatory of the contract
- An observer of the contract
- Has been granted visibility through a choice

### Error: Transitive Dependency Conflict

**Cause:** Multiple versions of the same package in the dependency tree.

**Solution:**
```bash
# Clean all dist folders
rm -rf daml/common/.daml/dist
rm -rf daml/cip56-token/.daml/dist
rm -rf daml/bridge-core/.daml/dist
rm -rf daml/bridge-wayfinder/.daml/dist

# Rebuild in order
cd daml/common && daml build --enable-multi-package=no
cd ../cip56-token && daml build --enable-multi-package=no
cd ../bridge-core && daml build --enable-multi-package=no
cd ../bridge-wayfinder && daml build --enable-multi-package=no
```

---

## Advanced Testing

### Adding Custom Test Scenarios

Create additional test functions in `Test.daml`:

```daml
-- Test partial withdrawal
testPartialWithdrawal : Script ()
testPartialWithdrawal = script do
  -- ... setup ...
  
  -- Lock only part of holdings
  (lockedCid, Some changeCid) <- submit alice do
    exerciseCmd holdingCid Lock with
      receiver = operator
      value = 50.0  -- Only withdraw half
      complianceRulesCid = None
  
  -- Verify change remains
  Some change <- queryContractId alice changeCid
  assertMsg "Change should be 50.0" (change.amount == 50.0)
  
  -- ... continue withdrawal ...
```

### Testing with Compliance Rules

```daml
-- Test with whitelist enabled
testWithCompliance : Script ()
testWithCompliance = script do
  -- ... setup ...
  
  -- Create compliance rules
  rulesCid <- submit issuer do
    createCmd ComplianceRules with
      issuer = issuer
      isWhitelistEnabled = True
      observers = [alice, bob]
  
  -- Issue proof to Alice
  aliceProofCid <- submit issuer do
    createCmd ComplianceProof with
      issuer = issuer
      user = alice
  
  -- Transfer with compliance
  (recipientCid, _) <- submit alice do
    exerciseCmd holdingCid Transfer with
      to = bob
      value = 10.0
      complianceRulesCid = Some rulesCid
      complianceProofCid = Some aliceProofCid
```

### Running Multiple Tests

```bash
# Run all test scripts
daml script --dar .daml/dist/bridge-wayfinder-1.0.0.dar \
  --script-name Wayfinder.Test:testWayfinderBridge --ide-ledger

daml script --dar .daml/dist/bridge-wayfinder-1.0.0.dar \
  --script-name Wayfinder.Test:testPartialWithdrawal --ide-ledger

daml script --dar .daml/dist/bridge-wayfinder-1.0.0.dar \
  --script-name Wayfinder.Test:testWithCompliance --ide-ledger
```

---

## Summary

| Test | Command | What it Validates |
|------|---------|-------------------|
| Full E2E | `Wayfinder.Test:testWayfinderBridge` | Complete bridge lifecycle |
| CIP-56 Token | `CIP56.Script:test` | Token minting, transfer, compliance |
| Bridge Core | `Bridge.Script:testBridgeFlow` | Core bridge contracts |

**Next Steps:**
1. Integrate with Go middleware for real EVM interaction
2. Deploy to Canton testnet
3. Add stress testing with multiple concurrent users

