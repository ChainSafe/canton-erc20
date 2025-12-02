# Issuer-Centric Bridge Model

This document describes the issuer-centric architecture for the Canton-EVM bridge, where the **issuer (participant node operator)** controls all party management and bridge operations.

## Overview

In this model:
- **End users do NOT manage Canton keys directly**
- The **issuer's participant node** signs all Canton transactions on behalf of users
- Users are identified by their **Canton fingerprints** (32-byte cryptographic identifiers)
- Users interact with the bridge via EVM only; Canton operations are handled by the issuer

## Key Concepts

### Canton Party Structure

A Canton Party ID consists of two parts:
```
hint::fingerprint
│     │
│     └── 32-byte cryptographic fingerprint (64-68 hex chars)
└──────── Human-readable identifier
```

Example:
```
Alice::1220f2fe29866fd6a0009ecc8a64ccdc09f1958bd0f801166baaee469d1251b2eb72
       └────────────────────────────────────────────────────────────────────────┘
                              Fingerprint (68 chars with multihash prefix)
```

### Issuer Responsibilities

1. **Party Allocation**: Issuer allocates Canton parties for users via `AllocateParty` API
2. **Fingerprint Knowledge**: Issuer knows fingerprints from `AllocatePartyResponse`
3. **Mapping Registration**: Issuer creates `FingerprintMapping` contracts in DAML
4. **Deposit Processing**: Issuer resolves fingerprints and mints tokens
5. **Withdrawal Processing**: Issuer burns tokens and creates events for EVM release

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ISSUER (Participant Node)                         │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  1. PARTY ALLOCATION                                                  │  │
│  │                                                                       │  │
│  │  AllocateParty("Alice")                                               │  │
│  │       │                                                               │  │
│  │       ▼                                                               │  │
│  │  Response: "Alice::1220f2fe29866fd6a..."                              │  │
│  │       │                                                               │  │
│  │       ▼                                                               │  │
│  │  Extract fingerprint: "1220f2fe29866fd6a..."                          │  │
│  │       │                                                               │  │
│  │       ▼                                                               │  │
│  │  Create FingerprintMapping { userParty=Alice, fingerprint=... }       │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  2. GIVE FINGERPRINT TO USER                                          │  │
│  │                                                                       │  │
│  │  Issuer → User: "Your fingerprint is 1220f2fe29866fd6a..."            │  │
│  │                  "Use this when depositing on EVM"                    │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                             DEPOSIT FLOW                                     │
│                                                                             │
│  ┌──────────┐    ┌──────────────┐    ┌────────────┐    ┌───────────────┐   │
│  │   USER   │───▶│  EVM Bridge  │───▶│ Middleware │───▶│ Canton/DAML   │   │
│  │          │    │              │    │            │    │               │   │
│  │ deposits │    │ emits event  │    │ creates    │    │ resolves fp   │   │
│  │ w/ fp    │    │ w/ bytes32   │    │ Pending    │    │ mints tokens  │   │
│  └──────────┘    │ fingerprint  │    │ Deposit    │    │               │   │
│                  └──────────────┘    └────────────┘    └───────────────┘   │
│                                                                             │
│  EVM: depositToCanton(token, amount, bytes32(fingerprint))                  │
│  DAML: PendingDeposit → FingerprintMapping → CIP56Holding                   │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                           WITHDRAWAL FLOW                                    │
│                                                                             │
│  ┌──────────┐    ┌───────────────┐    ┌────────────┐    ┌──────────────┐   │
│  │   USER   │───▶│ Canton/DAML   │───▶│ Middleware │───▶│  EVM Bridge  │   │
│  │          │    │               │    │            │    │              │   │
│  │ requests │    │ issuer burns  │    │ processes  │    │ releases     │   │
│  │ withdraw │    │ creates event │    │ event      │    │ tokens       │   │
│  │ off-chain│    │               │    │            │    │              │   │
│  └──────────┘    └───────────────┘    └────────────┘    └──────────────┘   │
│                                                                             │
│  User requests withdrawal via UI/API (off-chain)                            │
│  DAML: WithdrawalRequest → WithdrawalEvent                                  │
│  EVM: releaseToEvm(token, amount, address)                                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## DAML Templates

### FingerprintMapping
Links a fingerprint to a Canton Party. Only issuer can create/modify.

```daml
template FingerprintMapping
  with
    issuer      : Party         -- Bridge issuer/operator
    userParty   : Party         -- Canton Party for the user
    fingerprint : Text          -- 32-byte fingerprint (hex)
    evmAddress  : Optional EvmAddress
  where
    signatory issuer
    observer userParty
```

### PendingDeposit
Created by middleware when EVM deposit event is detected.

```daml
template PendingDeposit
  with
    issuer      : Party
    fingerprint : Text          -- From EVM event
    amount      : Decimal
    evmTxHash   : Text
    tokenId     : Text
    createdAt   : Time
  where
    signatory issuer
```

### DepositReceipt
Created after successful fingerprint resolution.

```daml
template DepositReceipt
  with
    issuer      : Party
    recipient   : Party         -- Resolved from FingerprintMapping
    fingerprint : Text
    amount      : Decimal
    evmTxHash   : Text
    tokenId     : Text
    source      : ChainRef
  where
    signatory issuer
    observer recipient
```

## Implementation Details

### 1. Party Allocation (Issuer)

```go
// Middleware/Issuer code
response, err := partyManagement.AllocateParty(ctx, &AllocatePartyRequest{
    PartyIdHint: "Alice",
})
// response.PartyDetails.Party = "Alice::1220f2fe29866fd6a..."

// Extract fingerprint
parts := strings.Split(response.PartyDetails.Party, "::")
fingerprint := parts[1]  // "1220f2fe29866fd6a..."

// Create FingerprintMapping in DAML
// ...
```

### 2. User Registration (Off-chain)

Issuer provides user their fingerprint through a secure channel:
- User onboarding UI
- API response after KYC
- Secure messaging

### 3. EVM Deposit

User deposits with their fingerprint:
```solidity
// User calls this on Ethereum
bridge.depositToCanton(
    tokenAddress,
    amount,
    bytes32(fingerprint)  // Their Canton fingerprint
);
```

### 4. Deposit Processing (Middleware)

```go
// Middleware sees DepositToCanton event
event := parseDepositEvent(log)
fingerprint := hex.EncodeToString(event.CantonRecipient[:])

// Create PendingDeposit in DAML
// Look up FingerprintMapping by fingerprint
// Process deposit and mint tokens
```

### 5. Withdrawal Processing

```go
// User requests withdrawal off-chain (API/UI)
// Issuer creates WithdrawalRequest in DAML
// Issuer processes withdrawal → WithdrawalEvent
// Middleware sees event → releases on EVM
```

## Security Considerations

1. **Fingerprint Uniqueness**: Each fingerprint is cryptographically derived from the party's public key, ensuring uniqueness

2. **Issuer Authority**: Only the issuer can:
   - Allocate parties
   - Create fingerprint mappings
   - Process deposits/withdrawals
   - Mint/burn tokens

3. **Fingerprint Verification**: DAML asserts that `mapping.fingerprint == deposit.fingerprint` before minting

4. **Audit Trail**: All deposits/withdrawals include original fingerprint and EVM transaction hash

## SDK Compatibility

This implementation is compatible with **DAML SDK 3.4.x**:
- No contract keys used (deprecated in SDK 3.x)
- Lookups done via ContractId tracking in middleware
- All templates use standard DAML-LF 2.x features

## File Structure

```
contracts/canton-erc20/daml/
├── common/
│   └── src/Common/
│       ├── Types.daml           # Basic types (ChainRef, EvmAddress, etc.)
│       ├── FingerprintAuth.daml # FingerprintMapping, PendingDeposit, DepositReceipt
│       └── FingerprintAuthTest.daml
├── bridge-core/
│   └── src/Bridge/
│       └── Contracts.daml       # MintCommand, WithdrawalRequest, WithdrawalEvent
├── bridge-wayfinder/
│   └── src/Wayfinder/
│       ├── Bridge.daml          # WayfinderBridgeConfig
│       └── Test.daml            # Integration tests
└── cip56-token/
    └── src/CIP56/
        └── Token.daml           # CIP56Manager, CIP56Holding
```

## Testing

Run tests with:
```bash
cd contracts/canton-erc20/daml
./scripts/test-all.sh
```

Or individually:
```bash
cd contracts/canton-erc20/daml/common
daml build && daml test

cd contracts/canton-erc20/daml/bridge-wayfinder
daml build && daml test
```

