# Canton-Ethereum Token Bridge Implementation Plan

## Overview
Centralized token bridge connecting CIP-56 tokens (Canton Network) with ERC-20 tokens (Ethereum Mainnet), implemented as a single relayer node running as a sidecar to the Canton Network Partner Node.

## Architecture

### High-Level Components

```
┌─────────────────────────────────────────────────────────────┐
│                    Canton Network                            │
│  ┌──────────────┐         ┌─────────────────────────┐      │
│  │ CIP-56 Token │◄────────┤ Canton Bridge Contract  │      │
│  │  Contract    │         │ (Lock/Mint/Burn)        │      │
│  └──────────────┘         └──────────▲──────────────┘      │
│                                      │                       │
└──────────────────────────────────────┼───────────────────────┘
                                       │
                  ┌────────────────────┼────────────────────┐
                  │        Relayer Node (Go)                 │
                  │  ┌─────────────────────────────────┐    │
                  │  │ Canton Network Client           │    │
                  │  │  - Monitor CIP-56 events        │    │
                  │  │  - Privacy-aware interactions   │    │
                  │  │  - DvP settlement coordination  │    │
                  │  └─────────────────────────────────┘    │
                  │  ┌─────────────────────────────────┐    │
                  │  │ Event Processing Engine         │    │
                  │  │  - Cross-chain event matching   │    │
                  │  │  - State management             │    │
                  │  │  - Transaction orchestration    │    │
                  │  └─────────────────────────────────┘    │
                  │  ┌─────────────────────────────────┐    │
                  │  │ Ethereum Client                 │    │
                  │  │  - Monitor ERC-20 events        │    │
                  │  │  - Submit transactions          │    │
                  │  └─────────────────────────────────┘    │
                  │  ┌─────────────────────────────────┐    │
                  │  │ Security & State Store          │    │
                  │  │  - Pending transfers DB         │    │
                  │  │  - Nonce management             │    │
                  │  │  - Key management               │    │
                  │  └─────────────────────────────────┘    │
                  └────────────────────┼────────────────────┘
                                       │
┌──────────────────────────────────────┼───────────────────────┐
│                  Ethereum Mainnet    │                       │
│  ┌──────────────┐         ┌──────────▼──────────────┐       │
│  │ ERC-20 Token │◄────────┤ Ethereum Bridge Contract│       │
│  │  Contract    │         │ (Lock/Mint/Burn)        │       │
│  └──────────────┘         └─────────────────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

## Key Technical Considerations

### 1. Canton Network Integration

**CIP-56 Token Features to Support:**
- **Privacy-Preserving Transfers**: Bridge must handle privacy features where transaction details are shared on need-to-know basis
- **Multi-Step Transfers**: Support for token admin controls and receiver authorization
- **Atomic DvP Settlement**: Leverage Canton's native atomic delivery-vs-payment for secure cross-chain swaps

**Canton Partner Node Interaction:**
- Run relayer as sidecar process to Canton Partner Node
- Use Canton Network API/RPC for:
  - Monitoring CIP-56 token events (deposits, withdrawals)
  - Submitting transactions with proper authorization
  - Querying balances and transaction history
- Implement privacy-aware event monitoring (may need authorized access)

### 2. Ethereum Smart Contract Requirements

**Bridge Contract (Ethereum Side):**
```solidity
// Core functionality needed
- Lock/unlock mechanism for native tokens bridging to Canton
- Mint/burn mechanism for wrapped Canton tokens on Ethereum
- Event emissions for relayer monitoring
- Owner-controlled operations (emergency pause, fee adjustments)
- Nonce/sequence tracking for replay protection
- Fee collection mechanism
```

**Key Functions:**
- `depositToCanton(address token, uint256 amount, bytes32 cantonRecipient)`
- `withdrawFromCanton(address token, uint256 amount, address recipient, bytes proof)`
- `emergencyPause()` / `unpause()`

**Security Features:**
- Time locks for large transfers
- Rate limiting
- Multi-signature controls (future enhancement)
- Reentrancy guards

### 3. Canton Bridge Contract Requirements

**Canton Side Contract (CIP-56 Compatible):**
- Lock/unlock for Canton-native tokens bridging to Ethereum
- Mint/burn for wrapped Ethereum tokens on Canton
- Integration with Canton's privacy features
- Support for multi-step transfer authorization
- Leverage atomic DvP settlement

### 4. Relayer Node Responsibilities

**Core Functions:**

1. **Event Monitoring**
   - Monitor Canton bridge contract for deposit events
   - Monitor Ethereum bridge contract for deposit events
   - Track confirmations on both chains

2. **Transaction Processing**
   - Validate events and extract transfer details
   - Maintain state of pending transfers
   - Execute corresponding action on destination chain
   - Handle transaction failures and retries

3. **State Management**
   - Track nonces for each chain
   - Maintain database of pending/completed transfers
   - Handle reorgs on both chains

4. **Security Operations**
   - Secure key management for signing transactions
   - Validate proofs/signatures where applicable
   - Monitor for anomalous activity
   - Implement rate limiting and sanity checks

## Technology Stack

### Relayer (Go)
- **Blockchain Clients:**
  - Infura for Ethereum interaction
  - Canton Network SDK/API client (to be determined based on Canton documentation)
  
- **Database:**
  - PostgreSQL for state management
  - Redis for caching and job queues (optional)

- **Key Libraries:**
  - `chi` for REST API
  - `database/sql` for database ORM
  - `viper` for configuration management
  - `zap` for logging
  - `prometheus` client for metrics

### Smart Contracts
- **Ethereum:**
  - Solidity 0.8.x
  - Hardhat or Foundry for development/testing
  - OpenZeppelin contracts for standards and security

- **Canton:**
  - Canton smart contract language (Daml or similar - needs research)

## Project Structure

```
canton-middleware/
├── cmd/
│   ├── relayer/           # Main relayer application
│   └── tools/             # CLI tools for management
├── contracts/
│   ├── ethereum/          # Solidity contracts
│   │   ├── Bridge.sol
│   │   ├── test/
│   │   └── scripts/
│   └── canton/            # Canton contracts
│       └── BridgeContract.daml (or equivalent)
├── pkg/
│   ├── canton/            # Canton client and utilities
│   │   ├── client.go
│   │   ├── types.go
│   │   └── events.go
│   ├── ethereum/          # Ethereum client and utilities
│   │   ├── client.go
│   │   ├── contracts.go  # Generated contract bindings
│   │   └── events.go
│   ├── relayer/           # Core relayer logic
│   │   ├── engine.go
│   │   ├── processor.go
│   │   └── state.go
│   ├── db/                # Database models and queries
│   │   ├── models.go
│   │   └── store.go
│   └── config/            # Configuration handling
│       └── config.go
├── internal/
│   ├── metrics/           # Prometheus metrics
│   └── security/          # Key management, signing
├── deployments/           # Docker, k8s configs
├── docs/                  # Documentation
├── scripts/               # Deployment and utility scripts
├── go.mod
├── go.sum
└── README.md
```

## Security Considerations

### Centralized Bridge Risks

1. **Single Point of Failure**
   - Relayer node is critical - if it goes down, bridge stops
   - Mitigation: Robust monitoring, auto-restart, high availability setup

2. **Key Management**
   - Relayer holds keys to both Canton and Ethereum contracts
   - Mitigation: Hardware security modules (HSM), secure enclaves, or cloud KMS
   - Multi-signature enhancement for future

3. **Trust Assumption**
   - Users must trust the relayer operator
   - Mitigation: Transparency (event logs), audits, gradual decentralization path

### Operational Security

1. **Transaction Validation**
   - Verify sufficient confirmations before processing
   - Canton: Understand finality model
   - Ethereum: 12-64 blocks depending on risk tolerance

2. **Replay Protection**
   - Implement nonce/sequence tracking on both chains
   - Validate event uniqueness

3. **Rate Limiting**
   - Prevent drain attacks
   - Set max transfer amounts per transaction/time period

4. **Emergency Controls**
   - Pause functionality on both contracts
   - Manual intervention procedures
   - Incident response plan

5. **Monitoring & Alerts**
   - Real-time monitoring of bridge balances
   - Alert on suspicious activity
   - Transaction anomaly detection

## Implementation Phases

### Phase 1: Research & Setup (Week 1-2)
- [ ] Deep dive into Canton Network documentation and APIs
- [ ] Identify Canton smart contract language and development tools
- [ ] Set up development environment
- [ ] Create basic project structure
- [ ] Design database schema for state management

### Phase 2: Smart Contract Development (Week 3-5)
- [ ] Develop Ethereum bridge contract
  - [ ] Lock/unlock mechanism
  - [ ] Mint/burn for wrapped tokens
  - [ ] Event emissions
  - [ ] Security controls
- [ ] Develop Canton bridge contract (CIP-56 compatible)
  - [ ] Lock/unlock mechanism  
  - [ ] Integration with privacy features
  - [ ] DvP settlement support
- [ ] Write comprehensive tests for both contracts
- [ ] Security audit (internal review)

### Phase 3: Relayer Core Development (Week 6-9)
- [ ] Implement Canton client
  - [ ] Event monitoring
  - [ ] Transaction submission
  - [ ] Privacy-aware interactions
- [ ] Implement Ethereum client
  - [ ] Event monitoring with confirmation tracking
  - [ ] Transaction submission with gas management
- [ ] Build event processing engine
  - [ ] Cross-chain event matching
  - [ ] State management
  - [ ] Transaction orchestration
- [ ] Implement database layer
  - [ ] Pending transfers tracking
  - [ ] Completed transfers history
  - [ ] Nonce management

### Phase 4: Security & Operations (Week 10-11)
- [ ] Implement key management system
- [ ] Add metrics and monitoring (Prometheus)
- [ ] Build admin API/dashboard
- [ ] Implement emergency pause mechanisms
- [ ] Add comprehensive logging
- [ ] Create operational runbooks

### Phase 5: Testing & Integration (Week 12-14)
- [ ] End-to-end testing on testnets
  - [ ] Canton testnet ↔ Ethereum testnet
- [ ] Stress testing and performance optimization
- [ ] Reorg handling tests
- [ ] Failure scenario testing
- [ ] Security testing and penetration testing
- [ ] Integration with Canton Partner Node as sidecar

### Phase 6: Deployment & Launch (Week 15-16)
- [ ] Deploy contracts to mainnet
- [ ] Deploy relayer to production environment
- [ ] Initialize bridge with initial liquidity
- [ ] Gradual rollout with transfer limits
- [ ] Monitoring and on-call setup
- [ ] Public documentation and user guides

### Phase 7: Post-Launch (Ongoing)
- [ ] Monitor bridge operations 24/7
- [ ] Collect user feedback
- [ ] Performance optimization
- [ ] Security audits (external)
- [ ] Plan for decentralization (multi-relayer, governance)

## Open Questions & Research Needed

1. **Canton Network Specifics:**
   - What is the exact API/SDK for Canton Partner Node integration?
   - What programming language/framework for Canton smart contracts?
   - How does privacy affect event visibility for the relayer?
   - What is Canton's finality model and confirmation requirements?

2. **Multi-Step Transfer Integration:**
   - How to configure the bridge as authorized sender/receiver?
   - What authorization flows are needed from token admins?

3. **Atomic DvP:**
   - How to implement cross-chain DvP settlement?
   - What coordination protocol between Canton and Ethereum?

4. **Token Mapping:**
   - How to handle multiple token pairs?
   - Registry of supported CIP-56 ↔ ERC-20 mappings?

5. **Fee Model:**
   - Bridge fee structure?
   - Gas cost handling on both chains?

## Success Criteria

- [ ] Successfully transfer CIP-56 tokens from Canton to Ethereum as wrapped ERC-20
- [ ] Successfully transfer ERC-20 tokens from Ethereum to Canton as wrapped CIP-56
- [ ] Handle 100+ transfers without failures
- [ ] Maintain 99.9% uptime for relayer
- [ ] Average transfer time < 5 minutes
- [ ] Zero security incidents or lost funds
- [ ] Comprehensive monitoring and alerting in place

## Next Steps

1. Acquire Canton Network documentation and developer resources
2. Set up Canton testnet access and Partner Node
3. Begin smart contract development in parallel with relayer foundation
4. Establish testing infrastructure
