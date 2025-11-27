# Canton-ERC20 Bridge: Architecture Diagrams

**Visual guide to the system architecture**

---

## Table of Contents

1. [Current vs Proposed Architecture](#current-vs-proposed-architecture)
2. [Multi-Package Structure](#multi-package-structure)
3. [Bridge Flow Diagrams](#bridge-flow-diagrams)
4. [CIP-56 Token Patterns](#cip-56-token-patterns)
5. [Integration Architecture](#integration-architecture)
6. [Security & Control Flow](#security--control-flow)

---

## Current vs Proposed Architecture

### Current Architecture (Single Package)

```
┌─────────────────────────────────────────────────────────────┐
│                    daml/ERC20/                              │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │   Token.daml │  │Allowance.daml│  │  Types.daml     │  │
│  │              │  │              │  │                 │  │
│  │ - Manager    │  │ - Allowance  │  │ - TokenMeta     │  │
│  │ - Holding    │  │   template   │  │                 │  │
│  │ - Mint/Burn  │  │              │  │                 │  │
│  │ - Transfer   │  │              │  │                 │  │
│  └──────────────┘  └──────────────┘  └─────────────────┘  │
│                                                             │
│  ┌────────────────────────────────────────────────────┐    │
│  │              Bridge/                                │    │
│  │                                                     │    │
│  │  ┌─────────────┐  ┌──────────────┐  ┌──────────┐  │    │
│  │  │Types.daml   │  │Contracts.daml│  │Script.daml│ │    │
│  │  │             │  │              │  │          │  │    │
│  │  │- ChainRef   │  │- MintProposal│  │- Tests   │  │    │
│  │  │- Direction  │  │- Redeem      │  │          │  │    │
│  │  │- EvmAddress │  │- BurnEvent   │  │          │  │    │
│  │  └─────────────┘  └──────────────┘  └──────────┘  │    │
│  └────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘

Issues:
❌ Not CIP-56 compliant
❌ Single token type only
❌ No multi-asset support
❌ Limited security controls
❌ Monolithic structure
```

### Proposed Architecture (Multi-Package)

```
┌─────────────────────────────────────────────────────────────────────┐
│                         daml/ (workspace)                            │
│                                                                      │
│  ┌────────────┐     ┌─────────────────┐     ┌──────────────────┐   │
│  │  common/   │────>│  cip56-token/   │────>│  bridge-core/    │   │
│  │            │     │                 │     │                  │   │
│  │ - Types    │     │ - CIP56Manager  │     │ - Registry       │   │
│  │ - Utils    │     │ - CIP56Holding  │     │ - Operator       │   │
│  │            │     │ - Transfer      │     │ - Deposit        │   │
│  └────────────┘     │ - Admin         │     │ - Withdrawal     │   │
│                     │ - Compliance    │     │ - Security       │   │
│                     │ - Metadata      │     │ - Fees           │   │
│                     └─────────────────┘     └──────────────────┘   │
│                              │                        │             │
│                              │                        │             │
│         ┌────────────────────┴────────────────────────┴────┐        │
│         │                    │                   │         │        │
│         ▼                    ▼                   ▼         ▼        │
│  ┌─────────────┐    ┌─────────────┐    ┌──────────────┐  ┌─────┐  │
│  │bridge-usdc/ │    │bridge-cbtc/ │    │bridge-generic│  │dvp/ │  │
│  │             │    │             │    │              │  │     │  │
│  │- xReserve   │    │- BitSafe    │    │- Dynamic     │  │- DvP│  │
│  │- CIP-86     │    │- Vaults     │    │  Registration│  │     │  │
│  └─────────────┘    └─────────────┘    └──────────────┘  └─────┘  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │              integration-tests/                            │     │
│  │  - End-to-end tests spanning all packages                 │     │
│  └────────────────────────────────────────────────────────────┘     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

Benefits:
✅ CIP-56 compliant
✅ Multi-asset support (USDC, CBTC, generic)
✅ Modular and reusable
✅ Comprehensive security
✅ Independent testing
```

---

## Multi-Package Structure

### Package Dependency Graph

```
                    ┌──────────┐
                    │  common  │
                    │          │
                    │ - Types  │
                    │ - Utils  │
                    └─────┬────┘
                          │
                          │ (data-dependency)
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
        ▼                 ▼                 ▼
  ┌──────────┐      ┌──────────┐      ┌──────────┐
  │cip56-token│      │   dvp    │      │   ...    │
  │          │      │          │      │          │
  │- Token   │      │- DvP     │      │          │
  │- Transfer│      │- Escrow  │      │          │
  │- Admin   │      │          │      │          │
  └────┬─────┘      └──────────┘      └──────────┘
       │
       │ (data-dependency)
       │
       ├─────────────────────────┬─────────────────────────┐
       │                         │                         │
       ▼                         ▼                         ▼
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│bridge-core  │         │             │         │             │
│             │         │             │         │             │
│- Registry   │         │             │         │             │
│- Deposit    │         │             │         │             │
│- Withdrawal │         │             │         │             │
│- Security   │         │             │         │             │
└──────┬──────┘         │             │         │             │
       │                │             │         │             │
       │ (data-dependency)            │         │             │
       │                │             │         │             │
   ┌───┴────┬───────────┴─┐       ┌───┴────┐    │             │
   │        │             │       │        │    │             │
   ▼        ▼             ▼       ▼        ▼    ▼             │
┌────────┐ ┌────────┐  ┌────────────┐  ┌──────────────┐      │
│bridge- │ │bridge- │  │bridge-     │  │              │      │
│usdc    │ │cbtc    │  │generic     │  │              │      │
│        │ │        │  │            │  │              │      │
│xReserve│ │BitSafe │  │Registration│  │              │      │
└────────┘ └────────┘  └────────────┘  │              │      │
                                        │              │      │
                                        │              │      │
           ┌────────────────────────────┴──────────────┴──────┘
           │
           ▼
    ┌──────────────────┐
    │integration-tests │
    │                  │
    │ All packages     │
    └──────────────────┘
```

### Package Build Order

```
1. common              (no dependencies)
   │
2. cip56-token, dvp    (depend on common)
   │
3. bridge-core         (depends on common, cip56-token)
   │
4. bridge-usdc         (depends on common, cip56-token, bridge-core)
   bridge-cbtc         (depends on common, cip56-token, bridge-core)
   bridge-generic      (depends on common, cip56-token, bridge-core)
   │
5. integration-tests   (depends on all packages)
```

---

## Bridge Flow Diagrams

### Ethereum → Canton (Deposit Flow)

```
┌──────────────┐         ┌──────────────┐         ┌──────────────┐
│   Ethereum   │         │      Go      │         │   Canton     │
│   Mainnet    │         │  Middleware  │         │   Network    │
└──────┬───────┘         └──────┬───────┘         └──────┬───────┘
       │                        │                        │
       │ 1. User deposits       │                        │
       │    USDC to bridge      │                        │
       │    contract            │                        │
       │◄───────────────────────┤                        │
       │                        │                        │
       │ 2. Deposit event       │                        │
       ├───────────────────────>│                        │
       │    emitted             │                        │
       │                        │                        │
       │                        │ 3. Monitor event       │
       │                        │    Verify confirmations│
       │                        │    (12+ blocks)        │
       │                        │                        │
       │                        │ 4. Create MintProposal │
       │                        ├───────────────────────>│
       │                        │    - operator signs    │
       │                        │    - includes ref      │
       │                        │                        │
       │                        │                        │ 5. MintProposal
       │                        │                        │    created
       │                        │                        │    (operator sig)
       │                        │                        │
       │                        │ 6. Stream events       │
       │                        │<───────────────────────┤
       │                        │    (observe proposal)  │
       │                        │                        │
       │                        │                        │
User   │                        │                        │ 7. User accepts
action │                        │                        │    (via UI/API)
       │                        │                        │◄──────────────
       │                        │                        │
       │                        │                        │ 8. MintAuthorization
       │                        │                        │    created
       │                        │                        │    (operator + user sig)
       │                        │                        │
       │                        │ 9. Stream events       │
       │                        │<───────────────────────┤
       │                        │    (observe auth)      │
       │                        │                        │
       │                        │ 10. Exercise MintOnCanton
       │                        ├───────────────────────>│
       │                        │                        │
       │                        │                        │ 11. CIP56Holding
       │                        │                        │     created
       │                        │                        │     User has USDC!
       │                        │                        │
       │                        │ 12. Confirm success    │
       │                        │<───────────────────────┤
       │                        │                        │
```

### Canton → Ethereum (Withdrawal Flow)

```
┌──────────────┐         ┌──────────────┐         ┌──────────────┐
│   Canton     │         │      Go      │         │   Ethereum   │
│   Network    │         │  Middleware  │         │   Mainnet    │
└──────┬───────┘         └──────┬───────┘         └──────┬───────┘
       │                        │                        │
       │ 1. User creates        │                        │
       │    WithdrawalRequest   │                        │
       │◄───────────────────────│                        │
       │    - burns holding     │                        │
       │    - specifies EVM addr│                        │
       │                        │                        │
       │ 2. WithdrawalRequest   │                        │
       │    created             │                        │
       │                        │                        │
       │ 3. Stream events       │                        │
       ├───────────────────────>│                        │
       │    (observe request)   │                        │
       │                        │                        │
       │                        │ 4. Verify request      │
       │                        │    - check balance     │
       │                        │    - validate addr     │
       │                        │                        │
       │ 5. Exercise ApproveBurn│                        │
       │<───────────────────────┤                        │
       │    (operator signs)    │                        │
       │                        │                        │
       │ 6. BurnEvent created   │                        │
       │    - holding burned    │                        │
       │    - event emitted     │                        │
       │                        │                        │
       │ 7. Stream events       │                        │
       ├───────────────────────>│                        │
       │    (observe burn)      │                        │
       │                        │                        │
       │                        │ 8. Build Ethereum tx   │
       │                        │    - release tokens    │
       │                        │    - sign with operator│
       │                        │                        │
       │                        │ 9. Submit tx           │
       │                        ├───────────────────────>│
       │                        │                        │
       │                        │                        │ 10. Tx mined
       │                        │                        │     User receives
       │                        │                        │     USDC on Ethereum
       │                        │                        │
       │                        │ 11. Confirm (12 blocks)│
       │                        │<───────────────────────┤
       │                        │                        │
       │ 12. Record completion  │                        │
       │<───────────────────────┤                        │
       │                        │                        │
```

---

## CIP-56 Token Patterns

### Multi-Step Transfer Pattern

```
     Alice                 Issuer/Admin              Bob
       │                        │                     │
       │ 1. ProposeTransfer     │                     │
       ├───────────────────────>│                     │
       │    (Alice signs)       │                     │
       │                        │                     │
       │                        │ 2. Check compliance │
       │                        │    - whitelist      │
       │                        │    - limits         │
       │                        │    - KYC/AML        │
       │                        │                     │
       │                        │ 3. AdminAuthorize   │
       │                        │    (if required)    │
       │                        │                     │
       │                        │ 4. Notify Bob       │
       │                        ├────────────────────>│
       │                        │                     │
       │                        │ 5. Bob accepts      │
       │                        │<────────────────────┤
       │                        │    (Bob signs)      │
       │                        │                     │
       │                        │ 6. Execute transfer │
       │                        │    - burn Alice's   │
       │                        │    - mint Bob's     │
       │                        │                     │
       │ 7. Transfer complete   │ 8. Transfer complete│
       │<───────────────────────┤────────────────────>│
       │                        │                     │
       
Privacy: Only Alice, Bob, and Issuer see this transfer
         Carol has no visibility of this transaction
```

### Token Admin Controls

```
┌─────────────────────────────────────────────────────────────┐
│                    CIP56Manager                             │
│                    (Token Admin)                            │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │    Mint      │  │    Burn      │  │  UpdateConfig   │  │
│  │  (admin only)│  │  (admin only)│  │   (admin only)  │  │
│  └──────┬───────┘  └──────┬───────┘  └────────┬────────┘  │
│         │                 │                    │           │
└─────────┼─────────────────┼────────────────────┼───────────┘
          │                 │                    │
          ▼                 ▼                    ▼
    ┌──────────┐      ┌──────────┐        ┌──────────┐
    │  Holding │      │  Holding │        │ Config   │
    │  Created │      │  Archived│        │ Updated  │
    └──────────┘      └──────────┘        └──────────┘

Admin can:
✅ Mint new tokens (with authorization)
✅ Burn tokens (with user consent)
✅ Update compliance rules
✅ Manage whitelist
✅ Pause/unpause transfers
✅ Update metadata

Admin cannot:
❌ Transfer user tokens without consent
❌ Bypass compliance rules
❌ See private transfers they're not party to
```

### Compliance & Whitelist Flow

```
                    ┌─────────────────┐
                    │  ComplianceRules│
                    │                 │
                    │ - whitelist     │
                    │ - daily limits  │
                    │ - transfer rules│
                    └────────┬────────┘
                             │
                             │ (checked on every transfer)
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
   ┌──────────┐        ┌──────────┐       ┌──────────┐
   │Whitelisted│        │ Transfer │       │  Daily   │
   │  Check   │───────>│  Amount  │──────>│  Limit   │
   │          │  pass  │  Check   │ pass  │  Check   │
   └────┬─────┘        └────┬─────┘       └────┬─────┘
        │ fail             │ fail              │ fail
        │                  │                   │
        ▼                  ▼                   ▼
   ┌────────────────────────────────────────────────┐
   │         Transfer Rejected                       │
   │         (with specific error message)           │
   └────────────────────────────────────────────────┘
                             │
                             │ all checks pass
                             ▼
                    ┌─────────────────┐
                    │ Transfer Proposal│
                    │    Created       │
                    └──────────────────┘
```

---

## Integration Architecture

### Full System Architecture

```
┌───────────────────────────────────────────────────────────────┐
│                        Ethereum Mainnet                       │
│                                                               │
│  ┌──────────────┐         ┌─────────────────────────────┐   │
│  │   USDC       │◄────────┤  ERC20 Bridge Contract      │   │
│  │   ERC20      │         │                             │   │
│  │   Contract   │         │  - Lock/Unlock              │   │
│  │              │         │  - Mint/Burn (wrapped)      │   │
│  └──────────────┘         │  - Event emission           │   │
│                           │  - Fee collection           │   │
│                           │  - Pause mechanism          │   │
│                           └────────────┬────────────────┘   │
└────────────────────────────────────────┼────────────────────┘
                                         │
                                         │ Events ↓ | Txs ↑
                                         │
             ┌───────────────────────────┼───────────────────────────┐
             │                      Go Middleware                     │
             │                     (Bridge Relayer)                   │
             │                                                        │
             │  ┌──────────────────────────────────────────────────┐ │
             │  │         Event Processing Engine                   │ │
             │  │  - Monitor Ethereum (Deposit/Burn events)        │ │
             │  │  - Monitor Canton (Withdrawal/Mint events)       │ │
             │  │  - Cross-chain coordination                      │ │
             │  │  - Retry logic and error handling                │ │
             │  └──────────────────────────────────────────────────┘ │
             │                                                        │
             │  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐ │
             │  │  Ethereum    │  │   Canton     │  │   State     │ │
             │  │  Client      │  │   Client     │  │   Store     │ │
             │  │  (Web3)      │  │  (gRPC)      │  │  (Postgres) │ │
             │  └──────────────┘  └──────┬───────┘  └─────────────┘ │
             │                           │                           │
             └───────────────────────────┼───────────────────────────┘
                                         │
                                         │ Commands ↓ | Events ↑
                                         │
┌────────────────────────────────────────┼────────────────────────────┐
│                          Canton Network                             │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                Canton Participant Node                          │ │
│  │                                                                  │ │
│  │  ┌────────────────────────────────────────────────────────┐   │ │
│  │  │            Daml Ledger (CIP-56 Tokens)                  │   │ │
│  │  │                                                          │   │ │
│  │  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │   │ │
│  │  │  │  USDC    │  │  CBTC    │  │ Generic  │  │  ...   │ │   │ │
│  │  │  │ CIP-56   │  │ CIP-56   │  │ CIP-56   │  │        │ │   │ │
│  │  │  │  Token   │  │  Token   │  │  Token   │  │        │ │   │ │
│  │  │  └──────────┘  └──────────┘  └──────────┘  └────────┘ │   │ │
│  │  │                                                          │   │ │
│  │  │  ┌─────────────────────────────────────────────────┐   │   │ │
│  │  │  │          Bridge Contracts                       │   │   │ │
│  │  │  │  - Registry                                     │   │   │ │
│  │  │  │  - Deposit/Withdrawal                           │   │   │ │
│  │  │  │  - Security Controls                            │   │   │ │
│  │  │  └─────────────────────────────────────────────────┘   │   │ │
│  │  └────────────────────────────────────────────────────────┘   │ │
│  │                                                                  │ │
│  │  ┌────────────────────────────────────────────────────────┐   │ │
│  │  │          Ledger API (gRPC)                              │   │ │
│  │  │  - TransactionService (event streaming)                │   │ │
│  │  │  - CommandService (submit transactions)                │   │ │
│  │  │  - ActiveContractsService (query state)                │   │ │
│  │  └────────────────────────────────────────────────────────┘   │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                  Canton Domain                                  │ │
│  │   - Sequencer (ordering)                                       │ │
│  │   - Mediator (consensus)                                       │ │
│  │   - Privacy enforcement                                        │ │
│  └────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
```

### Data Flow: Deposit Example

```
User     Ethereum      Go           Canton       Daml
 │          │      Middleware        API        Ledger
 │          │           │             │           │
 │ Deposit  │           │             │           │
 │─────────>│           │             │           │
 │          │           │             │           │
 │          │ Event     │             │           │
 │          │──────────>│             │           │
 │          │           │             │           │
 │          │           │Verify       │           │
 │          │           │(12 blocks)  │           │
 │          │           │             │           │
 │          │           │CreateMint   │           │
 │          │           │Proposal     │           │
 │          │           ├────────────>│           │
 │          │           │             │           │
 │          │           │             │ Create    │
 │          │           │             │MintProposal
 │          │           │             ├──────────>│
 │          │           │             │           │
 │          │           │             │           │ Contract
 │          │           │             │           │ stored
 │          │           │             │           │
 │          │           │Stream       │           │
 │          │           │Events       │           │
 │          │           │<────────────┤           │
 │          │           │             │           │
 │ Accept   │           │             │           │
 │Proposal  │           │             │           │
 │──────────┼───────────┼────────────>│           │
 │          │           │             │           │
 │          │           │             │ Accept    │
 │          │           │             ├──────────>│
 │          │           │             │           │
 │          │           │             │           │ MintAuth
 │          │           │             │           │ created
 │          │           │             │           │
 │          │           │Stream       │           │
 │          │           │<────────────┤           │
 │          │           │             │           │
 │          │           │Mint         │           │
 │          │           │OnCanton     │           │
 │          │           ├────────────>│           │
 │          │           │             │           │
 │          │           │             │ Mint      │
 │          │           │             ├──────────>│
 │          │           │             │           │
 │          │           │             │           │ Holding
 │          │           │             │           │ created
 │          │           │             │           │
 │<─────────┴───────────┴─────────────┴───────────┘
 │                                                 │
 │            User now has CIP-56 token!          │
```

---

## Security & Control Flow

### Emergency Pause Mechanism

```
                    ┌─────────────────┐
                    │BridgeController │
                    │                 │
                    │  paused: Bool   │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
   ┌─────────┐         ┌─────────┐         ┌─────────┐
   │ Deposit │         │Withdrawal│         │Transfer │
   │         │         │         │         │         │
   │ Check   │         │ Check   │         │ Check   │
   │ !paused │         │ !paused │         │ !paused │
   └────┬────┘         └────┬────┘         └────┬────┘
        │                   │                   │
        │ paused = true     │ paused = true    │ paused = true
        ▼                   ▼                   ▼
   ┌────────────────────────────────────────────────┐
   │           All operations blocked                │
   │           "Bridge is paused"                    │
   └────────────────────────────────────────────────┘

Operator Actions:
┌────────────┐          ┌────────────┐
│   Pause    │          │  Unpause   │
│            │          │            │
│ Emergency  │◄────────>│  Resume    │
│  stop all  │          │ operations │
└────────────┘          └────────────┘
```

### Rate Limiting Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    RateLimiter                              │
│                                                             │
│  Current Daily Volume: 100,000 USDC                        │
│  Daily Limit: 1,000,000 USDC                               │
│  Per-Transaction Limit: 50,000 USDC                        │
│  Cooldown: None                                            │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ New transfer: 75,000 USDC
                         │
            ┌────────────┴────────────┐
            │                         │
            ▼                         ▼
    ┌───────────────┐         ┌──────────────┐
    │ Check daily   │         │ Check per-tx │
    │ limit         │         │ limit        │
    │               │         │              │
    │ 100k + 75k    │         │ 75k ≤ 50k?