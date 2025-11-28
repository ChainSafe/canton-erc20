# GitHub Issues for Canton-EVM Bridge

Copy each issue below into GitHub Issues at:
https://github.com/ChainSafe/canton-erc20/issues/new

---

## Issue 1: USDC Bridge Implementation

**Title:** `[Feature] USDC Bridge - Circle xReserve Integration`

**Labels:** `enhancement`, `bridge`, `usdc`, `priority:high`

**Milestone:** v1.1.0

**Description:**

```markdown
## Summary

Implement the USDC bridge for Circle xReserve integration, enabling USDC transfers between Ethereum and Canton Network.

## Requirements

- [ ] Implement `USDCBridgeConfig` template in `bridge-usdc` package
- [ ] Define USDC metadata (ERC20 contract address, decimals: 6)
- [ ] Add Circle attestation verification hooks (placeholder for xReserve)
- [ ] Implement CIP-86 compliance requirements
- [ ] Create E2E test suite (`USDC.Test:testUSDCBridge`)
- [ ] Add TESTING.md documentation

## Technical Details

**EVM Contract:** TBD (Circle USDC on target chain)
**Decimals:** 6
**Compliance:** CIP-86 (Circle xReserve attestation)

## Dependencies

- Requires `bridge-core` (completed)
- Requires `cip56-token` (completed)

## Acceptance Criteria

1. All tests pass
2. Privacy validation completed
3. Documentation updated
4. CHANGELOG.md updated

## References

- [Circle xReserve](https://www.circle.com/en/cross-chain-transfer-protocol)
- [Requirements Doc](docs/sow/usdc.md)
```

---

## Issue 2: cBTC Bridge Implementation

**Title:** `[Feature] cBTC Bridge - BitSafe Vault Integration`

**Labels:** `enhancement`, `bridge`, `cbtc`, `priority:high`

**Milestone:** v1.2.0

**Description:**

```markdown
## Summary

Implement the cBTC bridge for BitSafe vault integration, enabling wrapped Bitcoin transfers between Ethereum and Canton Network.

## Requirements

- [ ] Implement `CBTCBridgeConfig` template in `bridge-cbtc` package
- [ ] Define cBTC metadata (ERC20 contract address, decimals: 8)
- [ ] Add BitSafe vault verification hooks
- [ ] Implement custody workflow patterns
- [ ] Create E2E test suite (`CBTC.Test:testCBTCBridge`)
- [ ] Add TESTING.md documentation

## Technical Details

**EVM Contract:** TBD (BitSafe cBTC)
**Decimals:** 8
**Custody:** BitSafe vault integration

## Dependencies

- Requires `bridge-core` (completed)
- Requires `cip56-token` (completed)

## Acceptance Criteria

1. All tests pass
2. Privacy validation completed
3. Documentation updated
4. CHANGELOG.md updated

## References

- [Requirements Doc](docs/sow/cbtc.md)
```

---

## Issue 3: Generic ERC20 Bridge

**Title:** `[Feature] Generic ERC20 Bridge - Dynamic Token Registration`

**Labels:** `enhancement`, `bridge`, `generic`, `priority:medium`

**Milestone:** v1.3.0

**Description:**

```markdown
## Summary

Implement a generic ERC20 bridge supporting dynamic token registration for any ERC20 token.

## Requirements

- [ ] Implement `GenericBridgeConfig` template in `bridge-generic` package
- [ ] Add `TokenRegistry` for dynamic token registration
- [ ] Implement configurable metadata mapping
- [ ] Support arbitrary ERC20 tokens
- [ ] Create E2E test suite with multiple token types
- [ ] Add TESTING.md documentation

## Technical Details

**Supported Tokens:** Any ERC20
**Registration:** Dynamic via `TokenRegistry`
**Metadata:** Configurable per token

## Dependencies

- Requires `bridge-core` (completed)
- Requires `cip56-token` (completed)

## Acceptance Criteria

1. All tests pass with multiple token types
2. Privacy validation completed
3. Documentation updated
4. CHANGELOG.md updated

## References

- [ERC-20 Standard](https://eips.ethereum.org/EIPS/eip-20)
- [Requirements Doc](docs/sow/evm.md)
```

---

## Issue 4: DvP Settlement Integration

**Title:** `[Feature] DvP Settlement - Atomic Cross-Asset Swaps`

**Labels:** `enhancement`, `dvp`, `priority:medium`

**Milestone:** v2.0.0

**Description:**

```markdown
## Summary

Implement Delivery vs Payment (DvP) settlement for atomic cross-asset swaps on Canton Network.

## Requirements

- [ ] Implement `DvPSettlement` template in `dvp` package
- [ ] Add escrow patterns for atomic settlement
- [ ] Support cross-asset swaps (e.g., PRIME <-> USDC)
- [ ] Integrate with bridge contracts
- [ ] Create E2E test suite for settlement scenarios
- [ ] Add TESTING.md documentation

## Technical Details

**Settlement:** Canton-native atomic settlement
**Assets:** Any CIP-56 compliant tokens
**Pattern:** Escrow-based DvP

## Dependencies

- Requires `cip56-token` (completed)
- Requires at least 2 bridge implementations

## Acceptance Criteria

1. Atomic settlement verified
2. No partial execution possible
3. Privacy validation completed
4. Documentation updated

## References

- [Canton Settlement](https://docs.canton.network/)
```

---

## Issue 5: Go Middleware Integration

**Title:** `[Feature] Go Middleware Integration - Event Streaming`

**Labels:** `enhancement`, `middleware`, `integration`, `priority:high`

**Milestone:** v1.1.0

**Description:**

```markdown
## Summary

Integrate DAML contracts with Go middleware for event streaming and command submission.

## Requirements

- [ ] Define gRPC event streaming interface for `BurnEvent`
- [ ] Define command submission interface for `MintProposal`
- [ ] Document integration patterns
- [ ] Create integration test harness
- [ ] Add deployment configuration

## Technical Details

**Event Streaming:** Ledger gRPC API
**Command Submission:** Ledger gRPC API
**State Management:** External database

## Integration Points

### Events to Stream (Canton -> Middleware)
- `BurnEvent` - Triggers EVM unlock/mint

### Commands to Submit (Middleware -> Canton)
- `MintProposal` - After EVM lock detected
- `ApproveBurn` - After validation

## Acceptance Criteria

1. Middleware can observe `BurnEvent` contracts
2. Middleware can create `MintProposal` contracts
3. End-to-end flow works with real Canton node

## References

- [DAML Ledger API](https://docs.daml.com/app-dev/ledger-api.html)
- [Architecture Doc](docs/DAML_ARCHITECTURE_PROPOSAL.md)
```

---

## Issue 6: CI/CD Pipeline Setup

**Title:** `[Infra] CI/CD Pipeline - GitHub Actions`

**Labels:** `infrastructure`, `ci-cd`, `priority:medium`

**Milestone:** v1.1.0

**Description:**

```markdown
## Summary

Set up GitHub Actions CI/CD pipeline for automated building and testing.

## Requirements

- [ ] Create `.github/workflows/ci.yml`
- [ ] Build all DAML packages
- [ ] Run all tests
- [ ] Fail on test failures
- [ ] Cache DAML SDK for faster builds
- [ ] Add status badge to README

## Workflow Triggers

- Push to `main`, `develop`
- Pull requests to `main`, `develop`

## Example Workflow

```yaml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup DAML
        uses: digital-asset/setup-daml@v1
        with:
          version: '2.10.2'
      - name: Build
        run: ./scripts/build-all.sh
      - name: Test
        run: ./scripts/test-all.sh
```

## Acceptance Criteria

1. CI runs on every PR
2. Tests must pass to merge
3. Build artifacts cached
```

---

## Issue 7: Enhanced Compliance Rules

**Title:** `[Feature] Enhanced Compliance Rules - Multi-Jurisdiction Support`

**Labels:** `enhancement`, `compliance`, `priority:low`

**Milestone:** v2.0.0

**Description:**

```markdown
## Summary

Enhance compliance rules to support multi-jurisdiction requirements and advanced KYC/AML patterns.

## Requirements

- [ ] Add jurisdiction-based rules
- [ ] Implement transfer limits per jurisdiction
- [ ] Add time-based restrictions (e.g., holding periods)
- [ ] Support multiple compliance providers
- [ ] Create compliance audit trail

## Technical Details

**Jurisdictions:** US, EU, APAC (configurable)
**Limits:** Per-transaction, daily, monthly
**Audit:** Immutable compliance event log

## Dependencies

- Requires `cip56-token` (completed)

## Acceptance Criteria

1. Multi-jurisdiction rules work correctly
2. Audit trail is complete
3. Privacy preserved (no global observer)
```

---

## Issue 8: Security Audit Preparation

**Title:** `[Security] Prepare for External Security Audit`

**Labels:** `security`, `audit`, `priority:high`

**Milestone:** v1.0.1

**Description:**

```markdown
## Summary

Prepare codebase for external security audit.

## Requirements

- [ ] Document all authorization patterns
- [ ] Create threat model document
- [ ] Review all signatory/observer declarations
- [ ] Verify no information leakage
- [ ] Document key management requirements
- [ ] Create security checklist

## Areas to Review

1. **Authorization**
   - All choices have correct controllers
   - No unauthorized state changes possible

2. **Privacy**
   - Need-to-know visibility enforced
   - No global observers

3. **Integrity**
   - No double-spending possible
   - Atomic operations where required

## Deliverables

- [ ] SECURITY.md document
- [ ] Threat model diagram
- [ ] Authorization matrix

## Acceptance Criteria

1. All security documentation complete
2. No known vulnerabilities
3. Ready for external auditor
```

---

## Suggested Milestones

Create these milestones in GitHub:

| Milestone | Target Date | Description |
|-----------|-------------|-------------|
| v1.0.1 | +2 weeks | Security audit prep, bug fixes |
| v1.1.0 | +4 weeks | USDC Bridge, Go Middleware integration |
| v1.2.0 | +8 weeks | cBTC Bridge |
| v1.3.0 | +12 weeks | Generic ERC20 Bridge |
| v2.0.0 | +16 weeks | DvP Settlement, Enhanced Compliance |

---

## Suggested Labels

Create these labels in GitHub:

| Label | Color | Description |
|-------|-------|-------------|
| `bridge` | `#0052CC` | Bridge-related issues |
| `usdc` | `#2684FF` | USDC specific |
| `cbtc` | `#FF8B00` | cBTC specific |
| `generic` | `#6554C0` | Generic ERC20 |
| `dvp` | `#00875A` | DvP settlement |
| `compliance` | `#FF5630` | Compliance/KYC/AML |
| `middleware` | `#36B37E` | Go middleware |
| `infrastructure` | `#97A0AF` | CI/CD, tooling |
| `security` | `#DE350B` | Security related |
| `priority:high` | `#FF5630` | High priority |
| `priority:medium` | `#FFAB00` | Medium priority |
| `priority:low` | `#36B37E` | Low priority |

