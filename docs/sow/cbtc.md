# Bridging CBTC from Canton to Ethereum

**Overview:**
This memo outlines an SoW for bridging **CBTC** BitSafe’s wrapped Bitcoin token on Canton (a CIP-56 compliant asset) over to **Ethereum**. The goal is to extend CBTC’s utility into Ethereum’s DeFi ecosystem while maintaining security and institutional compliance. 

The proposed approach uses a straightforward bridge architecture (an ERC-20 contract on Ethereum plus an off-chain oracle service) and leverages Canton’s **participant node signing** model (so end-users don’t manage keys directly). Below we detail the bridge design, ChainSafe’s implementation steps, BitSafe’s responsibilities, and future enhancement opportunities.

## Bridge Architecture Overview

The **CBTC bridge** will consist of two main components:
1. **ERC-20 smart contract** on Ethereum representing CBTC
2. **Off-chain middleware oracle** that relays transactions between Canton and Ethereum

### Flow:

* **Canton to Ethereum:**
  * CBTC is **locked** on Canton
  * Oracle detects this and **mints** CBTC ERC-20 on Ethereum
* **Ethereum to Canton:**
  * CBTC ERC-20 is **burned** on Ethereum
  * Oracle detects this and **releases** CBTC on Canton

This ensures total supply parity and maintains CBTC’s 1:1 Bitcoin backing.

## Canton Participant Node Signatures (No End-User Keys)

End-users do not manage cryptographic keys. Instead:

* **Participant nodes** operated by BitSafe **sign on behalf of users**
* Bridge operations (burn/mint) are **executed by BitSafe's node**
* Oracle interacts with the participant node to relay authorized actions

This aligns with institutional custody practices and simplifies UX.

## ChainSafe’s Implementation Steps

### 1. Ethereum Smart Contract Development

* Develop ERC-20 CBTC contract (using OpenZeppelin)
* Include **mint/burn access control**
* Internal audit; deploy to testnet then mainnet

### 2. Off-Chain Middleware (Oracle) Setup

* Listen to:
  * Canton: lock/release events
  * Ethereum: burn/mint transactions
* Relay transactions between chains
* Implement:
  * Idempotency
  * Failure handling
  * Retry logic

### 3. Testing & QA

* Testnet end-to-end flows (lock-mint, burn-release)
* Validate:
  * Supply parity
  * Signature correctness
  * User experience
* BitSafe performs UAT

### 4. Mainnet Deployment

* Final deployment of:
  * ERC-20 contract
  * Oracle infrastructure
* Perform small-volume dry-run
* ChainSafe provides launch support and monitoring scripts

## BitSafe’s Role and Responsibilities

### Validator Key Management

* Manage Canton participant node keys
* Manage Ethereum oracle/contract keys
* Ensure secure storage and access controls

### Oracle Infrastructure & Operations

* Host the middleware
* Ensure:
  * High availability
  * Connectivity to Canton and Ethereum
  * Logging and alerts

### Gas Provisioning

* Fund Ethereum accounts for gas fees
* Monitor and top-up balances as needed

### UAT and Launch Support

* Participate in testing
* Prepare user documentation
* Coordinate deployment with ChainSafe

## Future Enhancement Opportunities (Post-MVP)

### Threshold Signatures

* Replace single key with multi-sig or FROST threshold signature scheme
* Explore the path of Ethereum light-clinet implementation on Canton
* Improve decentralization and security

### Trustless Verification via ZK-Proofs

* Validate Canton events via zk-proofs or Merkle-based SPV
* Reduce trust in oracles

### Additional Future Work

* GUI dashboards
* Rebalancing logic
* Monitoring tooling
