## Bridging Native USDC from Ethereum to Canton via xReserve and CIP-86

### Overview

This proposal outlines how to bridge native ERC-20 USDC from Ethereum to the Canton network using the CIP-86 middleware architecture, Circle's xReserve infrastructure, and CIP-56 token issuance standards. The bridged USDC will be minted on Canton and can be held in Bitsafe vaults. The bridge is designed to be bidirectional, enabling full interoperability between Ethereum and Canton.

### Architecture Summary

#### Flow: Ethereum to Canton

1. **User deposits native USDC into Circle's xReserve contract** on Ethereum.
2. **Circle's xReserve API signs an attestation** validating the deposit.
3. **Bridge middleware verifies the attestation** and submits a transaction to Canton to mint a CIP-56-compliant USDC token.
4. **CIP-56 USDC is minted to the user** or designated Bitsafe vault on Canton.

#### Flow: Canton to Ethereum

1. **User burns CIP-56 USDC** on Canton via the bridge.
2. **Bridge middleware detects the burn** and submits a withdrawal request to Circle’s xReserve API.
3. **xReserve verifies the burn** and provides a signed attestation.
4. **User redeems native ERC-20 USDC** on Ethereum using Circle’s minting protocol.

### Technical Components

#### CIP-56 USDC Token on Canton

* Implements ERC-20-equivalent interface: `transfer`, `approve`, `transferFrom`, etc.
* Supports privacy-aware transfers, institutional compliance features, and on-ledger authorization.
* Token admin (issuer) should be a multi-sig or threshold-key held by Bitsafe/attestors.
* Minting and burning are gated by validated xReserve attestations.

#### Bridge Middleware (Off-chain)

* Listens for xReserve on-chain events on Ethereum.
* Verifies Circle xReserve API attestation signatures.
* Triggers minting/burning on Canton using Canton Ledger API.
* Maintains replay protection, nonce tracking, and idempotency.

#### Bitsafe Vault Integration

* Minted CIP-56 USDC can be sent directly to Bitsafe custody accounts.
* Vault mechanics integrate with Bitsafe’s CIP-56 token controls.
* Tokens may be whitelisted to authorized vaults only.

### Token Identity and Metadata

* Symbol: `USDC` or `CUSDC`
* Decimals: 6 (matching Ethereum)
* Optional metadata fields: ISIN, xReserve contract address, issuer DTI code
* Compliance hooks for transfer restrictions (CIP-56 approvals)

### xReserve Integration

* Deposit-and-Mint: user deposits into xReserve on Ethereum; bridge mints on Canton.
* Burn-and-Withdraw: user burns on Canton; bridge triggers xReserve mint to Ethereum.
* All flows are secured via Circle-signed attestations.

### Privacy and Signature Model

* CIP-56 enforces visibility only to involved parties.
* Issuance and redemption must be co-signed by a threshold of attestors.
* Relayers and Bitsafe attestor nodes operate under a FROST-like signature scheme.

### Implementation Plan

1. Deploy CIP-56 USDC token on Canton.
2. Integrate xReserve monitoring and attestation processing in middleware.
3. Update bridge logic to support USDC flows using CIP-86 patterns.
4. Implement minting logic upon validated deposit.
5. Implement burn-and-redeem flow.
6. Register USDC metadata and compliance fields.
7. Integrate Bitsafe custody and vault workflows.
8. QA testnet validation and mainnet deployment.

### Future Considerations

* zk-proof attestation validation
* Circle-verified AML/KYC linkage on CIP-56 transfers
* Liquidity rebalancing across multiple chains

### Conclusion

This plan leverages CIP-86 and CIP-56 standards to enable fast, secure, and compliant bridging of native ERC-20 USDC from Ethereum into the Canton network. It uses Circle’s xReserve as the mint/burn oracle and ensures regulatory alignment via privacy-aware token design and attestations. USDC becomes natively usable on Canton and interoperable with Bitsafe custody and institutional finance tooling.
