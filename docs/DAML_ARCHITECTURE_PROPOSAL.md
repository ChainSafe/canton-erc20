# DAML Bridge Architecture Analysis & Proposal

**Author**: Development Team  
**Date**: 2024  
**Status**: Proposal

---

## Executive Summary

This document analyzes the current Canton-ERC20 bridge implementation and proposes a comprehensive restructuring to support the full scope of requirements outlined in the SOW documents. The goal is to create a testable, modular DAML implementation that supports multiple token types (USDC, CBTC, generic ERC20) with CIP-56 compliance, while remaining testable independently of the Go middleware.

---

## Table of Contents

1. [Current State Analysis](#current-state-analysis)
2. [Gap Analysis](#gap-analysis)
3. [Proposed Architecture](#proposed-architecture)
4. [Repository Restructuring](#repository-restructuring)
5. [Implementation Phases](#implementation-phases)
6. [Testing Strategy](#testing-strategy)
7. [Integration Points](#integration-points)
8. [Success Criteria](#success-criteria)

---

## Current State Analysis

### What Exists

#### 1. Basic ERC20 Implementation (`daml/ERC20/`)

**Token.daml**:
- ✅ `TokenManager` template with `Mint` and `Burn` choices
- ✅ `TokenHolding` template with `Transfer` choice
- ✅ Change calculation (returns remaining balance)
- ✅ Basic assertions (amount > 0, sufficient balance)

**Types.daml**:
- ✅ `TokenMeta` with name, symbol, decimals

**Allowance.daml**:
- ✅ `Allowance` template with `Decrease` choice
- ✅ Owner + Issuer signatory pattern

**Script.daml**:
- ✅ `test` script for basic mint/transfer flow
- ✅ `inspect` script for querying holdings
- ✅ Party allocation helpers

#### 2. Bridge Foundation (`daml/ERC20/Bridge/`)

**Types.daml**:
- ✅ `ChainRef` data type (chainName + eventId)
- ✅ `BridgeDirection` enum (ToCanton | ToEvm)
- ✅ `EvmAddress` newtype

**Contracts.daml**:
- ✅ `MintProposal` / `MintAuthorization` (two-step mint pattern)
- ✅ `RedeemRequest` / `BurnEvent` (burn-and-redeem pattern)
- ✅ Contract keys for deduplication (reference-based)
- ✅ Observer patterns for middleware visibility

**Script.daml**:
- ✅ `bridgeFlow` script demonstrating EVM→Canton→EVM cycle
- ✅ Uses proposal/acceptance pattern

#### 3. Supporting Infrastructure

- ✅ Go indexer with Ledger gRPC API integration
- ✅ Node.js middleware for REST/gRPC queries
- ✅ Bootstrap scripts for local development
- ✅ Comprehensive documentation

### Current Strengths

1. **Good Foundation**: The two-step proposal/acceptance pattern is correct for multi-party consent
2. **Contract Keys**: Proper use of keys for deduplication (prevents replay attacks)
3. **Observer Pattern**: Middleware visibility is properly configured
4. **Testability**: Scripts demonstrate the pattern works end-to-end
5. **Monorepo Structure**: Keeps Daml and middleware in sync

### Current Limitations

1. **Not CIP-56 Compliant**: Missing privacy, multi-step authorization, compliance hooks
2. **Single Token Focus**: No registry or multi-asset support
3. **No Fee Handling**: Bridge operations don't account for fees
4. **Limited Security**: No pause mechanism, rate limiting, or emergency controls
5. **No DvP Support**: Missing atomic settlement patterns
6. **Minimal Metadata**: No ISIN, DTI codes, or regulatory identifiers

---

## Gap Analysis

### Requirements from SOW vs. Current Implementation

| Requirement | SOW Docs | Current State | Gap |
|-------------|----------|---------------|-----|
| **CIP-56 Compliance** | ✓ Required | ✗ Missing | HIGH |
| - Privacy-preserving transfers | ✓ | ✗ | HIGH |
| - Multi-step authorization | ✓ | Partial | MED |
| - Token admin controls | ✓ | ✗ | HIGH |
| - Receiver authorization | ✓ | ✗ | MED |
| **Multi-Asset Support** | ✓ Required | ✗ Missing | HIGH |
| - USDC (xReserve/CIP-86) | ✓ | ✗ | HIGH |
| - CBTC (BitSafe wrapped BTC) | ✓ | ✗ | HIGH |
| - Generic ERC20 | ✓ | Partial | MED |
| **Bridge Security** | ✓ Required | Partial | HIGH |
| - Nonce/replay protection | ✓ | Partial (keys) | LOW |
| - Emergency pause | ✓ | ✗ | HIGH |
| - Rate limiting | ✓ | ✗ | MED |
| - Fee collection | ✓ | ✗ | MED |
| **Atomic DvP Settlement** | ✓ Required | ✗ Missing | MED |
| **Token Registry** | ✓ Required | ✗ Missing | HIGH |
| **Comprehensive Testing** | ✓ Required | Basic | MED |
| - Privacy tests | ✓ | ✗ | HIGH |
| - Multi-party scenarios | ✓ | ✗ | HIGH |
| - DvP tests | ✓ | ✗ | MED |

### Key Missing Components

#### 1. CIP-56 Token Standard
- No privacy-aware transfer patterns
- Missing token admin role and controls
- No receiver authorization workflow
- Lacks compliance/whitelisting hooks
- No support for multi-step transfers

#### 2. Token Registry & Multi-Asset Management
- No way to register multiple token pairs
- Missing chain-to-chain mapping
- No metadata standards (ISIN, DTI codes)
- Can't distinguish USDC vs CBTC vs generic tokens

#### 3. Bridge Security & Controls
- No emergency pause functionality
- No rate limiting or daily caps
- Missing fee calculation and collection
- No operator key rotation support

#### 4. Advanced Bridge Features
- No xReserve attestation verification (for USDC)
- No BitSafe vault integration patterns (for CBTC)
- Missing atomic DvP patterns
- No multi-sig support (future)

---

## Proposed Architecture

### Design Principles

1. **Modularity**: Separate concerns into reusable packages
2. **CIP-56 First**: Build on compliant token standard
3. **Test-Driven**: Every feature must be testable via Daml scripts
4. **Middleware Independence**: Bridge logic works without Go middleware
5. **Privacy by Default**: Respect Canton's privacy model
6. **Extensibility**: Support future enhancements (multi-sig, ZK proofs)

### Package Structure

```
daml/
├── common/                          # Shared utilities
│   ├── Types.daml                   # Common data types
│   ├── Utils.daml                   # Helper functions
│   └── daml.yaml
│
├── cip56-token/                     # CIP-56 Token Standard
│   ├── Token.daml                   # CIP-56 compliant token
│   ├── Transfer.daml                # Multi-step transfer workflows
│   ├── Admin.daml                   # Token admin controls
│   ├── Compliance.daml              # Whitelisting/authorization
│   ├── Metadata.daml                # Extended metadata (ISIN, etc.)
│   ├── Scripts/
│   │   ├── BasicFlow.daml
│   │   ├── PrivacyTest.daml
│   │   └── ComplianceTest.daml
│   └── daml.yaml
│
├── bridge-core/                     # Core Bridge Logic
│   ├── Registry.daml                # Token pair registry
│   ├── Operator.daml                # Bridge operator role
│   ├── Deposit.daml                 # Lock/deposit workflows
│   ├── Withdrawal.daml              # Burn/withdrawal workflows
│   ├── Attestation.daml             # Event verification
│   ├── Security.daml                # Pause, rate limiting
│   ├── Fee.daml                     # Fee calculation/collection
│   ├── Scripts/
│   │   ├── DepositFlow.daml
│   │   ├── WithdrawalFlow.daml
│   │   ├── SecurityTest.daml
│   │   └── FeeTest.daml
│   └── daml.yaml
│
├── bridge-usdc/                     # USDC-Specific Bridge
│   ├── XReserve.daml                # xReserve attestation types
│   ├── USDCBridge.daml              # USDC bridge contract
│   ├── CIP86.daml                   # CIP-86 integration
│   ├── Scripts/
│   │   ├── DepositUSDC.daml
│   │   ├── RedeemUSDC.daml
│   │   └── XReserveTest.daml
│   └── daml.yaml
│
├── bridge-cbtc/                     # CBTC-Specific Bridge
│   ├── CBTCBridge.daml              # CBTC bridge contract
│   ├── BitSafeVault.daml            # Vault integration
│   ├── Scripts/
│   │   ├── DepositCBTC.daml
│   │   ├── RedeemCBTC.daml
│   │   └── VaultTest.daml
│   └── daml.yaml
│
├── bridge-generic/                  # Generic ERC20 Bridge
│   ├── GenericBridge.daml           # Generic token bridge
│   ├── TokenMapping.daml            # ERC20 ↔ CIP-56 mapping
│   ├── Scripts/
│   │   ├── RegisterToken.daml
│   │   ├── BridgeFlow.daml
│   │   └── MultiTokenTest.daml
│   └── daml.yaml
│
├── dvp/                             # Delivery vs Payment
│   ├── Settlement.daml              # Atomic DvP contracts
│   ├── Escrow.daml                  # DvP escrow
│   ├── Scripts/
│   │   └── DvPTest.daml
│   └── daml.yaml
│
├── integration-tests/               # Cross-package tests
│   ├── EndToEnd.daml
│   ├── MultiParty.daml
│   ├── CrossChain.daml
│   └── daml.yaml
│
└── multi-package.yaml               # Workspace config
```

### Core Design Patterns

#### 1. CIP-56 Token Pattern

```haskell
-- Privacy-aware holding with authorization
template CIP56Holding
  with
    issuer       : Party
    owner        : Party
    amount       : Decimal
    metadata     : ExtendedMetadata
    restrictions : ComplianceRules
  where
    signatory issuer, owner
    
    -- Multi-step transfer: propose → authorize → execute
    choice ProposeTransfer : ContractId TransferProposal
      with
        recipient : Party
        amount    : Decimal
      controller owner
      do
        -- Check compliance rules
        assertMsg "Transfer allowed" (canTransfer restrictions owner recipient)
        create TransferProposal with ...
    
    -- Support for token admin authorization
    choice RequireAdminApproval : ContractId AdminApprovalRequest
      controller owner
      do ...
```

#### 2. Bridge Registry Pattern

```haskell
-- Central registry for supported token pairs
template TokenRegistry
  with
    operator       : Party
    supportedPairs : [TokenPair]
  where
    signatory operator
    
    choice RegisterPair : ContractId TokenRegistry
      with
        evmToken    : EvmTokenInfo
        cantonToken : CantonTokenInfo
        config      : BridgeConfig
      controller operator
      do ...
    
    choice UpdateConfig : ContractId TokenRegistry
      with
        tokenSymbol : Text
        newConfig   : BridgeConfig
      controller operator
      do ...
```

#### 3. Attestation Pattern (for xReserve)

```haskell
-- Circle xReserve attestation verification
template XReserveAttestation
  with
    operator      : Party
    depositor     : Party
    amount        : Decimal
    attestation   : CircleAttestation
    verified      : Bool
  where
    signatory operator
    observer depositor
    
    choice VerifyAndMint : ContractId CIP56Holding
      with
        tokenManagerCid : ContractId CIP56Manager
      controller operator
      do
        assertMsg "Valid attestation" (verifyCircleSignature attestation)
        -- Mint CIP-56 USDC
        ...
```

#### 4. Emergency Controls Pattern

```haskell
-- Bridge pause mechanism
template BridgeController
  with
    operator : Party
    paused   : Bool
    config   : SecurityConfig
  where
    signatory operator
    
    choice Pause : ContractId BridgeController
      controller operator
      do
        create this with paused = True
    
    choice Unpause : ContractId BridgeController
      controller operator
      do
        create this with paused = False
    
    -- All bridge operations must check: assertMsg "not paused" (not paused)
```

#### 5. DvP Settlement Pattern

```haskell
-- Atomic delivery vs payment
template DvPProposal
  with
    buyer     : Party
    seller    : Party
    operator  : Party
    tokenCid  : ContractId CIP56Holding
    payment   : Decimal
  where
    signatory seller, operator
    observer buyer
    
    choice SettleDvP : (ContractId CIP56Holding, ContractId PaymentReceipt)
      controller buyer
      do
        -- Atomically transfer token and payment
        newTokenCid <- exercise tokenCid CIP56Transfer with ...
        receipt <- create PaymentReceipt with ...
        pure (newTokenCid, receipt)
```

---

## Repository Restructuring

### Directory Layout

```
canton-erc20/                        # Root
├── daml/                            # All Daml packages
│   ├── multi-package.yaml           # Workspace config
│   ├── common/
│   ├── cip56-token/
│   ├── bridge-core/
│   ├── bridge-usdc/
│   ├── bridge-cbtc/
│   ├── bridge-generic/
│   ├── dvp/
│   └── integration-tests/
│
├── indexer-go/                      # Go indexer (existing)
│   ├── cmd/
│   ├── pkg/
│   │   ├── canton/                  # Canton client
│   │   ├── db/                      # Database layer
│   │   └── api/                     # REST API
│   └── scripts/
│
├── middleware/                      # Bridge middleware (to be built)
│   ├── cmd/
│   │   └── relayer/                 # Main relayer
│   ├── pkg/
│   │   ├── canton/                  # Canton integration
│   │   ├── ethereum/                # Ethereum integration
│   │   ├── bridge/                  # Bridge logic
│   │   │   ├── usdc/
│   │   │   ├── cbtc/
│   │   │   └── generic/
│   │   ├── attestation/             # xReserve/attestation
│   │   └── security/                # Key management
│   └── config/
│
├── contracts/                       # Solidity contracts (to be added)
│   ├── ethereum/
│   │   ├── Bridge.sol
│   │   ├── USDCBridge.sol
│   │   ├── CBTCBridge.sol
│   │   └── test/
│   └── scripts/
│
├── scripts/                         # Deployment & ops
│   ├── bootstrap.sh
│   ├── deploy-canton.sh
│   ├── deploy-ethereum.sh
│   └── test-e2e.sh
│
├── docs/                            # Documentation
│   ├── sow/                         # Requirements (existing)
│   ├── architecture/                # Design docs
│   ├── guides/                      # How-to guides
│   └── api/                         # API references
│
├── deployments/                     # Infrastructure
│   ├── docker/
│   ├── k8s/
│   └── terraform/
│
├── dev-env.sh                       # Environment exports
└── README.md
```

### Multi-Package Configuration

**`daml/multi-package.yaml`**:
```yaml
projects:
  - common
  - cip56-token
  - bridge-core
  - bridge-usdc
  - bridge-cbtc
  - bridge-generic
  - dvp
  - integration-tests
```

### Package Dependencies

```
common
  └─> (no dependencies)

cip56-token
  └─> common

bridge-core
  ├─> common
  └─> cip56-token

bridge-usdc
  ├─> common
  ├─> cip56-token
  └─> bridge-core

bridge-cbtc
  ├─> common
  ├─> cip56-token
  └─> bridge-core

bridge-generic
  ├─> common
  ├─> cip56-token
  └─> bridge-core

dvp
  ├─> common
  └─> cip56-token

integration-tests
  ├─> (all above packages)
```

---

## Implementation Phases

### Phase 0: Foundation (Week 1-2)

**Goal**: Set up multi-package workspace and migrate existing code

**Tasks**:
- [ ] Create `multi-package.yaml`
- [ ] Create `daml/common/` package
  - [ ] Move `ERC20.Types` → `Common.Types`
  - [ ] Add utility functions
- [ ] Create package structure for all modules
- [ ] Update `daml.yaml` files with correct dependencies
- [ ] Verify all packages build
- [ ] Update bootstrap scripts

**Deliverables**:
- Multi-package workspace compiles
- Existing functionality still works
- Documentation updated

### Phase 1: CIP-56 Token Standard (Week 3-5)

**Goal**: Implement CIP-56 compliant token with privacy and compliance features

**Tasks**:
- [ ] **Token Core** (`cip56-token/Token.daml`)
  - [ ] `CIP56Manager` template (mint/burn with admin controls)
  - [ ] `CIP56Holding` template (holdings with metadata)
  - [ ] Extended metadata (ISIN, DTI codes, regulatory info)
  
- [ ] **Transfer Workflows** (`cip56-token/Transfer.daml`)
  - [ ] `TransferProposal` (multi-step transfer initiation)
  - [ ] `TransferAuthorization` (admin approval step)
  - [ ] `TransferExecution` (final transfer)
  - [ ] Privacy-aware observer patterns
  
- [ ] **Admin Controls** (`cip56-token/Admin.daml`)
  - [ ] Token admin role
  - [ ] Admin approval workflows
  - [ ] Configuration updates
  
- [ ] **Compliance** (`cip56-token/Compliance.daml`)
  - [ ] Whitelist management
  - [ ] Transfer restrictions
  - [ ] KYC/AML hooks
  - [ ] Receiver authorization

**Test Scripts**:
- [ ] `BasicFlow.daml` - mint, transfer, burn
- [ ] `PrivacyTest.daml` - verify privacy properties
- [ ] `MultiStepTest.daml` - multi-step transfers
- [ ] `ComplianceTest.daml` - whitelist enforcement
- [ ] `AdminTest.daml` - admin controls

**Deliverables**:
- CIP-56 compliant token package
- Comprehensive test coverage
- Documentation on CIP-56 features

### Phase 2: Bridge Core (Week 6-8)

**Goal**: Build reusable bridge infrastructure

**Tasks**:
- [ ] **Registry** (`bridge-core/Registry.daml`)
  - [ ] `TokenRegistry` template
  - [ ] Token pair registration
  - [ ] Bridge configuration per pair
  - [ ] Query functions
  
- [ ] **Operator** (`bridge-core/Operator.daml`)
  - [ ] `BridgeOperator` role
  - [ ] Operator authorization
  - [ ] Key rotation support
  
- [ ] **Deposit** (`bridge-core/Deposit.daml`)
  - [ ] `DepositRequest` (from EVM)
  - [ ] `DepositProposal` (operator verification)
  - [ ] `DepositAuthorization` (user acceptance)
  - [ ] Mint execution
  
- [ ] **Withdrawal** (`bridge-core/Withdrawal.daml`)
  - [ ] `WithdrawalRequest` (from Canton)
  - [ ] `WithdrawalApproval` (operator verification)
  - [ ] Burn execution
  - [ ] `ReleaseEvent` (for EVM)
  
- [ ] **Attestation** (`bridge-core/Attestation.daml`)
  - [ ] Event attestation types
  - [ ] Verification logic
  - [ ] Confirmation tracking
  
- [ ] **Security** (`bridge-core/Security.daml`)
  - [ ] `BridgeController` (pause/unpause)
  - [ ] Rate limiting
  - [ ] Daily caps
  - [ ] Emergency withdrawal
  
- [ ] **Fee** (`bridge-core/Fee.daml`)
  - [ ] Fee calculation
  - [ ] Fee collection
  - [ ] Fee distribution

**Test Scripts**:
- [ ] `RegistryTest.daml` - token registration
- [ ] `DepositFlow.daml` - EVM → Canton
- [ ] `WithdrawalFlow.daml` - Canton → EVM
- [ ] `SecurityTest.daml` - pause, rate limits
- [ ] `FeeTest.daml` - fee calculations

**Deliverables**:
- Core bridge package
- All workflows testable via scripts
- Security controls implemented

### Phase 3: USDC Bridge (Week 9-10)

**Goal**: Implement USDC-specific bridge with xReserve integration

**Tasks**:
- [ ] **xReserve Types** (`bridge-usdc/XReserve.daml`)
  - [ ] `CircleAttestation` data type
  - [ ] Attestation verification helpers
  - [ ] xReserve event types
  
- [ ] **USDC Bridge** (`bridge-usdc/USDCBridge.daml`)
  - [ ] Extends bridge-core patterns
  - [ ] xReserve-specific workflows
  - [ ] Attestation-gated minting
  
- [ ] **CIP-86 Integration** (`bridge-usdc/CIP86.daml`)
  - [ ] CIP-86 compliant patterns
  - [ ] Metadata standards
  - [ ] Regulatory identifiers

**Test Scripts**:
- [ ] `DepositUSDC.daml` - Ethereum USDC → Canton
- [ ] `RedeemUSDC.daml` - Canton → Ethereum USDC
- [ ] `XReserveTest.daml` - attestation verification
- [ ] `CIP86Test.daml` - CIP-86 compliance

**Deliverables**:
- USDC bridge package
- xReserve integration patterns
- CIP-86 compliance

### Phase 4: CBTC Bridge (Week 11-12)

**Goal**: Implement CBTC-specific bridge with BitSafe vault integration

**Tasks**:
- [ ] **CBTC Bridge** (`bridge-cbtc/CBTCBridge.daml`)
  - [ ] Extends bridge-core patterns
  - [ ] BitSafe-specific workflows
  
- [ ] **Vault Integration** (`bridge-cbtc/BitSafeVault.daml`)
  - [ ] Vault custody patterns
  - [ ] Authorized vault transfers
  - [ ] Whitelisted vault support

**Test Scripts**:
- [ ] `DepositCBTC.daml` - Ethereum CBTC → Canton
- [ ] `RedeemCBTC.daml` - Canton → Ethereum CBTC
- [ ] `VaultTest.daml` - vault integration
- [ ] `CustodyTest.daml` - custody patterns

**Deliverables**:
- CBTC bridge package
- BitSafe vault patterns
- Custody workflows

### Phase 5: Generic ERC20 Bridge (Week 13-14)

**Goal**: Support arbitrary ERC20 tokens

**Tasks**:
- [ ] **Generic Bridge** (`bridge-generic/GenericBridge.daml`)
  - [ ] Extends bridge-core
  - [ ] Dynamic token registration
  - [ ] Configurable metadata mapping
  
- [ ] **Token Mapping** (`bridge-generic/TokenMapping.daml`)
  - [ ] ERC20 → CIP-56 conversion
  - [ ] Metadata transformation
  - [ ] Symbol/name mapping

**Test Scripts**:
- [ ] `RegisterToken.daml` - register new token
- [ ] `BridgeFlow.daml` - full bridge cycle
- [ ] `MultiTokenTest.daml` - multiple tokens simultaneously

**Deliverables**:
- Generic bridge package
- Token registration workflow
- Multi-token support

### Phase 6: DvP Settlement (Week 15-16)

**Goal**: Atomic delivery vs payment

**Tasks**:
- [ ] **Settlement** (`dvp/Settlement.daml`)
  - [ ] `DvPProposal` template
  - [ ] Atomic swap logic
  - [ ] Multi-party coordination
  
- [ ] **Escrow** (`dvp/Escrow.daml`)
  - [ ] Token escrow
  - [ ] Payment escrow
  - [ ] Release conditions

**Test Scripts**:
- [ ] `DvPTest.daml` - atomic settlement
- [ ] `EscrowTest.daml` - escrow workflows
- [ ] `MultiPartyDvP.daml` - complex scenarios

**Deliverables**:
- DvP package
- Atomic settlement patterns
- Canton-native DvP support

### Phase 7: Integration & Testing (Week 17-18)

**Goal**: Comprehensive end-to-end testing

**Tasks**:
- [ ] **Integration Tests** (`integration-tests/`)
  - [ ] End-to-end bridge flows
  - [ ] Multi-party scenarios
  - [ ] Cross-chain coordination
  - [ ] Privacy verification
  - [ ] Error handling
  
- [ ] **Performance Testing**
  - [ ] High-volume transfers
  - [ ] Concurrent operations
  - [ ] Rate limiting validation
  
- [ ] **Documentation**
  - [ ] API documentation
  - [ ] Integration guides
  - [ ] Troubleshooting guides

**Deliverables**:
- Full integration test suite
- Performance benchmarks
- Complete documentation

---

## Testing Strategy

### Test Pyramid

```
                    ┌─────────────┐
                    │ Integration │  E2E flows, multi-party
                    │    Tests    │  (integration-tests/)
                    └─────────────┘
                  ┌───────────────────┐
                  │  Package Tests    │  Per-package scripts
                  │  (Scripts/)       │  (e.g., BasicFlow.daml)
                  └───────────────────┘
              ┌─────────────────────────────┐
              │   Unit Tests (Choices)      │  Individual choice
              │                             │  correctness
              └─────────────────────────────┘
```

### Test Categories

#### 1. Unit Tests (Choice-Level)

Test individual choices in isolation:

```haskell
-- Test mint amount validation
testMintValidation : Script ()
testMintValidation = script do
  operator <- allocateParty "Operator"
  let meta = defaultMeta
  tmCid <- submit operator $ createCmd CIP56Manager with ...
  
  -- Should succeed
  _ <- submit operator $ exerciseCmd tmCid Mint with amount = 100.0, ...
  
  -- Should fail
  submitMustFail operator $ exerciseCmd tmCid Mint with amount = -1.0, ...
```

#### 2. Package Tests (Workflow-Level)

Test complete workflows within a package:

```haskell
-- Test full transfer workflow
testMultiStepTransfer : Script ()
testMultiStepTransfer = script do
  issuer <- allocateParty "Issuer"
  alice <- allocateParty "Alice"
  bob <- allocateParty "Bob"
  
  -- 1. Mint to Alice
  holdingCid <- mintToAlice issuer alice 100.0
  
  -- 2. Alice proposes transfer to Bob
  proposalCid <- submit alice $ exerciseCmd holdingCid ProposeTransfer with ...
  
  -- 3. Admin authorizes (if required)
  authCid <- submit issuer $ exerciseCmd proposalCid AdminAuthorize
  
  -- 4. Bob accepts transfer
  newHoldingCid <- submit bob $ exerciseCmd authCid AcceptTransfer
  
  -- Verify Bob received tokens
  Some holding <- queryContractId bob newHoldingCid
  assertEq holding.owner bob
  assertEq holding.amount 100.0
```

#### 3. Integration Tests (Cross-Package)

Test interactions between packages:

```haskell
-- Test full bridge cycle with CIP-56 token
testBridgeCycleWithCIP56 : Script ()
testBridgeCycleWithCIP56 = script do
  operator <- allocateParty "BridgeOperator"
  alice <- allocateParty "Alice"
  
  -- 1. Register token pair
  registryCid <- registerUSDC operator
  
  -- 2. Deposit from Ethereum (simulate xReserve attestation)
  depositCid <- simulateEthereumDeposit operator alice 1000.0
  
  -- 3. Operator verifies and proposes mint
  proposalCid <- submit operator $ exerciseCmd depositCid VerifyAndPropose
  
  -- 4. Alice accepts (CIP-56 requires acceptance)
  holdingCid <- submit alice $ exerciseCmd proposalCid AcceptMint
  
  -- 5. Alice holds CIP-56 USDC on Canton
  verifyBalance alice "USDC" 1000.0
  
  -- 6. Alice requests withdrawal
  withdrawalCid <- submit alice $ createCmd WithdrawalRequest with ...
  
  -- 7. Operator approves and burns
  releaseCid <- submit operator $ exerciseCmd withdrawalCid ApproveAndBurn
  
  -- 8. Release event created for Ethereum
  verifyReleaseEvent releaseCid alice 1000.0
```

#### 4. Privacy Tests

Verify Canton's privacy guarantees:

```haskell
-- Test that Bob cannot see Alice's transfer to Carol
testPrivacyIsolation : Script ()
testPrivacyIsolation = script do
  issuer <- allocateParty "Issuer"
  alice <- allocateParty "Alice"
  bob <- allocateParty "Bob"
  carol <- allocateParty "Carol"
  
  -- Alice transfers to Carol
  aliceHoldingCid <- mintToAlice issuer alice 100.0
  carolHoldingCid <- transferTokens alice carol aliceHoldingCid 50.0
  
  -- Bob should NOT see Carol's holding
  bobView <- query @CIP56Holding bob
  assertEq (length bobView) 0  -- Bob sees nothing
  
  -- Carol sees her holding
  carolView <- query @CIP56Holding carol
  assertEq (length carolView) 1
```

#### 5. Security Tests

Verify security controls work:

```haskell
-- Test bridge pause mechanism
testBridgePause : Script ()
testBridgePause = script do
  operator <- allocateParty "Operator"
  alice <- allocateParty "Alice"
  
  controllerCid <- setupBridgeController operator
  
  -- Deposit should work when not paused
  depositCid <- submit operator $ createCmd DepositRequest with ...
  
  -- Pause the bridge
  pausedControllerCid <- submit operator $ exerciseCmd controllerCid Pause
  
  -- Deposit should fail when paused
  submitMustFail operator $ createCmd DepositRequest with ...
  
  -- Unpause
  activeControllerCid <- submit operator $ exerciseCmd pausedControllerCid Unpause
  
  -- Deposit should work again
  _ <- submit operator $ createCmd DepositRequest with ...
  pure ()
```

#### 6. Compliance Tests

Verify compliance rules are enforced:

```haskell
-- Test whitelist enforcement
testWhitelistEnforcement : Script ()
testWhitelistEnforcement = script do
  issuer <- allocateParty "Issuer"
  alice <- allocateParty "Alice"
  bob <- allocateParty "Bob"
  charlie <- allocateParty "Charlie"
  
  -- Set up token with whitelist (Alice and Bob whitelisted)
  tmCid <- setupCIP56WithWhitelist issuer [alice, bob]
  aliceHoldingCid <- mintToParty issuer alice 100.0
  
  -- Transfer to Bob (whitelisted) should succeed
  _ <- submit alice $ exerciseCmd aliceHoldingCid ProposeTransfer with 
    recipient = bob
    amount = 50.0
  
  -- Transfer to Charlie (not whitelisted) should fail
  submitMustFail alice $ exerciseCmd aliceHoldingCid ProposeTransfer with
    recipient = charlie
    amount = 50.0
```

### Test Execution Strategy

#### Local Development
```bash
# Test individual package
cd daml/cip56-token
daml test

# Test all packages
cd daml
daml test --all

# Test specific script
daml script --dar .daml/dist/cip56-token-1.0.0.dar \
  --script-name CIP56.Scripts.BasicFlow:testMint \
  --ledger-host localhost --ledger-port 6865
```

#### CI/CD Pipeline
```yaml
# .github/workflows/test.yml
name: DAML Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: digital-asset/daml-action@v1
        with:
          sdk-version: 2.10.2
      
      - name: Build all packages
        run: cd daml && daml build --all
      
      - name: Run unit tests
        run: cd daml && daml test --all
      
      - name: Start Canton Sandbox
        run: ./scripts/start-sandbox.sh
      
      - name: Run integration tests
        run: |
          cd daml/integration-tests
          daml script --dar .daml/dist/*.dar \
            --script-name Integration.EndToEnd:testFullBridgeCycle \
            --ledger-host localhost --ledger-port 6865
```

### Test Data & Fixtures

Create reusable test fixtures:

```haskell
-- daml/common/TestFixtures.daml
module Common.TestFixtures where

import Daml.Script

data TestParties = TestParties with
  operator : Party
  issuer   : Party
  alice    : Party
  bob      : Party
  carol    : Party

allocateTestParties : Script TestParties
allocateTestParties = script do
  operator <- allocatePartyWithHint "Operator" (PartyIdHint "operator")
  issuer <- allocatePartyWithHint "Issuer" (PartyIdHint "issuer")
  alice <- allocatePartyWithHint "Alice" (PartyIdHint "alice")
  bob <- allocatePartyWithHint "Bob" (PartyIdHint "bob")
  carol <- allocatePartyWithHint "Carol" (PartyIdHint "carol")
  pure TestParties with ..

data TestTokenMeta = TestTokenMeta with
  usdcMeta : ExtendedMetadata
  cbtcMeta : ExtendedMetadata
  ccnMeta  : ExtendedMetadata

createTestMetadata : TestTokenMeta
createTestMetadata = TestTokenMeta with
  usdcMeta = ExtendedMetadata with
    name = "USD Coin"
    symbol = "USDC"
    decimals = 6
    isin = Some "US1234567890"
    dtiCode = Some "DTI-USDC"
  cbtcMeta = ExtendedMetadata with
    name = "Canton BTC"
    symbol = "CBTC"
    decimals = 8
    isin = Some "US0987654321"
    dtiCode = Some "DTI-CBTC"
  ccnMeta = ExtendedMetadata with
    name = "Canton Coin"
    symbol = "CCN"
    decimals = 6
    isin = None
    dtiCode = None
```

---

## Integration Points

### 1. DAML ↔ Go Middleware

#### Event Streaming

**DAML Side**: Templates emit events through contract creation

```haskell
template BurnEvent
  with
    operator    : Party
    owner       : Party
    destination : EvmAddress
    amount      : Decimal
    reference   : Text
  where
    signatory operator
    observer owner
    -- Middleware observes as 'operator' party
```

**Go Side**: Ledger API streaming

```go
// pkg/canton/stream.go
type EventStream struct {
    client    ledger.TransactionServiceClient
    party     string
    offset    string
}

func (s *EventStream) StreamBurnEvents(ctx context.Context) (<-chan BurnEvent, error) {
    stream, err := s.client.GetTransactions(ctx, &ledger.GetTransactionsRequest{
        Filter: &ledger.TransactionFilter{
            FiltersByParty: map[string]*ledger.Filters{
                s.party: {
                    Inclusive: &ledger.InclusiveFilters{
                        TemplateIds: []*ledger.Identifier{
                            {
                                ModuleName: "Bridge.Contracts",
                                EntityName: "BurnEvent",
                            },
                        },
                    },
                },
            },
        },
        Begin: &ledger.LedgerOffset{
            Value: &ledger.LedgerOffset_Absolute{
                Absolute: s.offset,
            },
        },
    })
    // Parse events and emit on channel
}
```

#### Command Submission

**Go Side**: Submit commands to DAML

```go
// pkg/canton/commands.go
func (c *CantonClient) CreateMintProposal(ctx context.Context, req MintRequest) error {
    cmd := &ledger.Command{
        Command: &ledger.Command_Create{
            Create: &ledger.CreateCommand{
                TemplateId: &ledger.Identifier{
                    ModuleName: "Bridge.Contracts",
                    EntityName: "MintProposal",
                },
                CreateArguments: &ledger.Record{
                    Fields: []*ledger.RecordField{
                        {Label: "operator", Value: partyValue(c.operatorParty)},
                        {Label: "recipient", Value: partyValue(req.Recipient)},
                        {Label: "amount", Value: decimalValue(req.Amount)},
                        {Label: "reference", Value: textValue(req.TxHash)},
                        // ...
                    },
                },
            },
        },
    }
    
    return c.submitAndWait(ctx, cmd)
}
```

**DAML Side**: Contract responds to creation

```haskell
-- Automatically visible to operator and recipient
template MintProposal
  with
    operator  : Party
    recipient : Party
    -- ...
  where
    signatory operator
    observer recipient  -- Ensures recipient can see and accept
```

### 2. DAML ↔ Ethereum (via Go Middleware)

#### Ethereum → Canton Flow

```
Ethereum Contract        Go Middleware              Canton Ledger
      |                        |                          |
      |-- Deposit Event ------>|                          |
      |                        |-- Monitor EVM logs       |
      |                        |-- Verify confirmations   |
      |                        |-- CreateMintProposal --->|
      |                        |                          |-- MintProposal created
      |                        |                          |
      |                        |<-- Stream events --------|
      |                        |                          |
User accepts proposal          |                          |
      |                        |                          |<- AcceptMint choice
      |                        |                          |-- CIP56Holding created
```

#### Canton → Ethereum Flow

```
Canton Ledger           Go Middleware           Ethereum Contract
      |                        |                        |
      |<- WithdrawalRequest ---|                        |
      |-- Request created      |                        |
      |                        |<-- Stream events       |
      |                        |-- Verify request       |
      |-- ApproveAndBurn ----->|                        |
      |<- BurnEvent ---------->|                        |
      |                        |-- Build Eth tx ------->|
      |                        |                        |-- Release tokens
```

### 3. Multi-Party Coordination

DAML's multi-party signing enables trustless coordination:

```haskell
-- Requires both operator and user signatures
template MintAuthorization
  with
    operator  : Party
    recipient : Party
    amount    : Decimal
  where
    signatory operator, recipient  -- Both must sign!
    
    choice MintOnCanton : ContractId CIP56Holding
      controller operator
      do
        -- Only operator can execute, but recipient already consented
        -- by signing the authorization contract
        ...
```

This prevents:
- Operator minting without user consent
- User claiming mints they didn't request
- Replay attacks (contract keys)

### 4. Privacy Model

Canton's privacy ensures parties only see relevant contracts:

```haskell
-- Alice's transfer to Bob
template CIP56Holding
  where
    signatory issuer, owner
    observer recipient  -- Only recipient sees this
    
-- Carol never observes this contract
-- Middleware running as 'operator' only sees contracts
-- where operator is signatory or observer
```

Configure middleware party correctly:

```yaml
# config/middleware.yaml
canton:
  party: "BridgeOperatorParty::1234..."
  act_as: ["BridgeOperatorParty::1234..."]
  read_as: ["BridgeOperatorParty::1234..."]
```

---

## Success Criteria

### Functional Requirements

- [ ] **CIP-56 Compliance**
  - [ ] Privacy-preserving transfers work
  - [ ] Multi-step authorization functions correctly
  - [ ] Token admin controls are enforceable
  - [ ] Receiver authorization works
  - [ ] Compliance rules (whitelist) are enforced

- [ ] **Bridge Operations**
  - [ ] EVM → Canton deposits work for all token types
  - [ ] Canton → EVM withdrawals work for all token types
  - [ ] No tokens can be minted without valid source event
  - [ ] No tokens can be burned without proper authorization
  - [ ] Supply parity maintained (EVM locked = Canton minted)

- [ ] **Multi-Asset Support**
  - [ ] USDC bridge with xReserve attestation works
  - [ ] CBTC bridge with BitSafe vault integration works
  - [ ] Generic ERC20 tokens can be registered and bridged
  - [ ] Multiple tokens can operate simultaneously

- [ ] **Security**
  - [ ] Emergency pause works
  - [ ] Rate limiting enforces daily caps
  - [ ] Fee calculation and collection works
  - [ ] No replay attacks possible
  - [ ] Proper error handling and recovery

### Non-Functional Requirements

- [ ] **Testability**
  - [ ] 100% of bridge flows testable via Daml scripts
  - [ ] No Go middleware required for testing core logic
  - [ ] All error cases covered by tests
  - [ ] Privacy properties verified by tests

- [ ] **Performance**
  - [ ] Scripts complete in reasonable time (<30s each)
  - [ ] Concurrent operations don't cause contention
  - [ ] Ledger queries are efficient

- [ ] **Maintainability**
  - [ ] Clear separation of concerns across packages
  - [ ] Minimal coupling between packages
  - [ ] Comprehensive documentation
  - [ ] Code follows Daml best practices

- [ ] **Extensibility**
  - [ ] Easy to add new token types
  - [ ] Future multi-sig support possible
  - [ ] DvP patterns extensible
  - [ ] Can upgrade contracts without breaking changes

### Quality Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Test Coverage | >90% | Percentage of choices tested |
| Script Success Rate | 100% | All scripts pass on Canton Sandbox |
| Documentation Coverage | 100% | All templates and choices documented |
| Package Build Time | <2 min | Time to build all packages |
| Test Execution Time | <5 min | Time to run all test scripts |

---

## Next Steps

### Immediate Actions (Week 1)

1. **Review & Approval**
   - [ ] Review this proposal with team
   - [ ] Get stakeholder sign-off
   - [ ] Finalize priorities and timeline

2. **Environment Setup**
   - [ ] Create multi-package workspace
   - [ ] Set up CI/CD pipeline
   - [ ] Configure Canton Sandbox for testing

3. **Begin Phase 0**
   - [ ] Create `daml/multi-package.yaml`
   - [ ] Create `daml/common/` package structure
   - [ ] Migrate existing types to common package
   - [ ] Verify builds work

### Communication Plan

- **Daily Standups**: Progress updates, blockers
- **Weekly Demos**: Show working scripts to stakeholders
- **Phase Reviews**: Formal review at end of each phase
- **Documentation**: Keep docs updated as code evolves

### Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| CIP-56 spec unclear | HIGH | Early prototype, validate with Canton team |
| xReserve API changes | MED | Abstract attestation layer, version carefully |
| Performance issues | MED | Benchmark early, optimize hot paths |
| Canton version updates | LOW | Pin SDK version, test upgrades separately |
| Timeline slippage | MED | Prioritize core features, defer nice-to-haves |

---

## Appendix

### A. Glossary

- **CIP-56**: Canton Improvement Proposal for token standard
- **CIP-86**: Canton Improvement Proposal for USDC integration
- **DvP**: Delivery vs Payment (atomic settlement)
- **xReserve**: Circle's cross-chain USDC protocol
- **CBTC**: Canton Bitcoin (BitSafe's wrapped BTC)
- **Attestation**: Cryptographic proof of off-chain event

### B. References

- [CIP-56 Token Standard](https://www.canton.network/blog/what-is-cip-56-a-guide-to-cantons-token-standard)
- [Canton Documentation](https://docs.digitalasset.com/)
- [Daml Best Practices](https://docs.digitalasset.com/daml/best-practices/)
- [Circle xReserve](https://www.circle.com/en/cross-chain-transfer-protocol)
- SOW Documents (in `docs/sow/`)

### C. Sample Configuration Files

**`daml/multi-package.yaml`**:
```yaml
projects:
  - common
  - cip56-token
  - bridge-core
  - bridge-usdc
  - bridge-cbtc
  - bridge-generic
  - dvp
  - integration-tests
```

**`daml/cip56-token/daml.yaml`**:
```yaml
name: cip56-token
version: 1.0.0
sdk-version: 2.10.2

source: .
dependencies:
  - daml-prim
  - daml-stdlib
  - daml-script

data-dependencies:
  - ../common/.daml/dist/common-1.0.0.dar

build-options:
  - --target=2.1
```

**`daml/bridge-core/daml.yaml`**:
```yaml
name: bridge-core
version: 1.0.0
sdk-version: 2.10.2

source: .
dependencies:
  - daml-prim
  - daml-stdlib
  - daml-script

data-dependencies:
  - ../common/.daml/dist/common-1.0.0.dar
  - ../cip56-token/.daml/dist/cip56-token-1.0.0.dar

build-options:
  - --target=2.1
```

### D. Migration Checklist

Moving from current structure to proposed:

- [ ] **Backup current code**
  ```bash
  git checkout -b backup-pre-restructure
  git push origin backup-pre-restructure
  ```

- [ ] **Create new branch**
  ```bash
  git checkout -b feature/multi-package-restructure
  ```

- [ ] **Create package directories**
  ```bash
  mkdir -p daml/{common,cip56-token,bridge-core,bridge-usdc,bridge-cbtc,bridge-generic,dvp,integration-tests}
  ```

- [ ] **Move existing files**
  ```bash
  # Move types to common
  mv daml/ERC20/Types.daml daml/common/
  
  # Keep bridge as starting point
  cp -r daml/ERC20/Bridge/* daml/bridge-core/
  ```

- [ ] **Create daml.yaml for each package**
  - Set correct dependencies
  - Use data-dependencies for sibling packages
  - Pin SDK version

- [ ] **Create multi-package.yaml**
  - List all packages
  - Set correct build order

- [ ] **Test build**
  ```bash
  cd daml
  daml build --all
  ```

- [ ] **Update scripts**
  - Update bootstrap.sh to build all packages
  - Update test scripts

- [ ] **Update documentation**
  - Update README.md
  - Update integration docs
  - Add migration notes

- [ ] **Commit and push**
  ```bash
  git add .
  git commit -m "Restructure to multi-package architecture"
  git push origin feature/multi-package-restructure
  ```

---

## Conclusion

This proposal provides a comprehensive roadmap for building a production-grade, CIP-56 compliant token bridge that supports USDC, CBTC, and generic ERC20 tokens. The modular architecture ensures testability, maintainability, and extensibility while leveraging Canton's unique privacy and multi-party computation features.

**Key Benefits**:
1. ✅ **Testable without Go middleware** - Pure Daml scripts verify all logic
2. ✅ **CIP-56 compliant** - Meets Canton Network standards
3. ✅ **Multi-asset support** - USDC, CBTC, and generic ERC20
4. ✅ **Production-ready** - Security controls, fee handling, emergency pause
5. ✅ **Well-documented** - Comprehensive docs and examples
6. ✅ **Maintainable** - Clear separation of concerns, modular design

**Timeline**: 18 weeks from foundation to production-ready implementation

**Next Step**: Begin Phase 0 (Foundation) by creating the multi-package workspace and migrating existing code.
