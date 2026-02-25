# Canton-ERC20 Bridge Documentation

This directory contains documentation for the DAML smart contracts used in the Canton-EVM token bridge.

> **Note**: The Go middleware (API Server, Relayer) is maintained in the parent [canton-middleware](https://github.com/ChainSafe/canton-middleware) repository.

---

## Documentation Index

### Architecture

| Document | Description |
|----------|-------------|
| [ISSUER_CENTRIC_MODEL.md](./ISSUER_CENTRIC_MODEL.md) | **Key document** - How the issuer-centric bridge works |
| [DAML_ARCHITECTURE_PROPOSAL.md](./DAML_ARCHITECTURE_PROPOSAL.md) | Technical design and package structure |
| [ARCHITECTURE_DIAGRAMS.md](./ARCHITECTURE_DIAGRAMS.md) | Visual diagrams |

### Requirements (SOW)

| Document | Description |
|----------|-------------|
| [sow/BRIDGE_IMPLEMENTATION_PLAN.md](./sow/BRIDGE_IMPLEMENTATION_PLAN.md) | High-level bridge architecture |
| [sow/canton-integration.md](./sow/canton-integration.md) | Canton Network / gRPC API integration |

### Development

| Document | Description |
|----------|-------------|
| [middleware-bridge-architecture.md](./middleware-bridge-architecture.md) | Middleware integration patterns |

---

## Quick Start

### Build DAML Packages

```bash
# From canton-middleware root
./scripts/setup/build-dars.sh

# Or build individually
cd daml/common && daml build
cd ../cip56-token && daml build
cd ../bridge-core && daml build
cd ../bridge-wayfinder && daml build
```

### Run Tests

```bash
# Run all tests
./scripts/test-all.sh --verbose

# Or individual packages
cd daml/cip56-token-tests && daml test
cd daml/bridge-core-tests && daml test
cd daml/bridge-wayfinder-tests && daml test
```

---

## Package Structure

```
daml/
├── common/              # Shared types (TokenMeta, EvmAddress, FingerprintAuth)
├── cip56-token/         # CIP-56 token standard + unified TokenConfig + Events
├── bridge-core/         # Core bridge contracts (MintCommand, WithdrawalRequest)
├── bridge-wayfinder/    # Wayfinder PROMPT bridge
└── *-tests/             # Test packages (with daml-script)
```

---

## Key Concepts

### Issuer-Centric Model

The bridge uses an **issuer-centric model** where:
- End users do NOT manage Canton keys directly
- The issuer's participant node signs all Canton transactions on behalf of users
- Users are identified by their **Canton fingerprints** (keccak256 of EVM address)
- Users interact via MetaMask; Canton operations are handled by the middleware

See [ISSUER_CENTRIC_MODEL.md](./ISSUER_CENTRIC_MODEL.md) for details.

### CIP-56 Compliance

All tokens implement the Canton Improvement Proposal 56 standard:
- Privacy-preserving transfers
- Multi-step authorization
- Compliance hooks
- Receiver authorization

### Unified Token Architecture

All tokens (native or bridged) use the same core templates:

- **`TokenConfig`** (in `CIP56.Config`) -- holds a `CIP56Manager` reference and token metadata. Provides `IssuerMint` and `IssuerBurn` choices that produce unified `MintEvent`/`BurnEvent` audit trails. Optional fields (`evmTxHash`, `evmDestination`) distinguish native operations from bridge operations.
- **`MintEvent`/`BurnEvent`** (in `CIP56.Events`) -- unified audit events for all token operations.
- **`WayfinderBridgeConfig`** -- a thin EVM bridge layer. It holds a `tokenConfigCid` reference and delegates all minting and burning to `TokenConfig`. The bridge only handles EVM-specific concerns (fingerprint registration, deposit validation, withdrawal initiation).

To add a new bridged token, create a new `TokenConfig` instance with its own `CIP56Manager` and metadata, then create a bridge config module that holds a reference to that `TokenConfig`. The core mint/burn/event logic is shared and identical for every token.

---

## Deprecated Documentation

The following documents reference components that have been removed or moved:

| Document | Status |
|----------|--------|
| `dev-setup.md` | Outdated - references removed Go indexer and Node.js middleware |
| `startup-flow.md` | Outdated - references removed components |

For current setup instructions, see the [Local Interop Testing Guide](https://github.com/ChainSafe/canton-middleware/blob/main/docs/LOCAL_INTEROP_TESTING.md).
