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
| [sow/usdc.md](./sow/usdc.md) | USDC bridging requirements |
| [sow/cbtc.md](./sow/cbtc.md) | cBTC bridging requirements |
| [sow/evm.md](./sow/evm.md) | Generic ERC20 bridging |

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
# Wayfinder bridge test
cd daml/bridge-wayfinder-tests
daml script \
  --dar .daml/dist/bridge-wayfinder-tests-1.1.0.dar \
  --script-name Wayfinder.Test:testWayfinderBridge \
  --ide-ledger
```

---

## Package Structure

```
daml/
├── common/              # Shared types (TokenMeta, EvmAddress, FingerprintAuth)
├── cip56-token/         # CIP-56 token standard
├── bridge-core/         # Core bridge contracts
├── bridge-wayfinder/    # Wayfinder PROMPT bridge [PRODUCTION]
├── bridge-usdc/         # USDC bridge [WIP]
├── bridge-cbtc/         # cBTC bridge [WIP]
├── bridge-generic/      # Generic ERC20 [WIP]
├── native-token/        # Native Canton tokens (DEMO)
├── dvp/                 # Delivery vs Payment
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

---

## Deprecated Documentation

The following documents reference components that have been removed or moved:

| Document | Status |
|----------|--------|
| `dev-setup.md` | Outdated - references removed Go indexer and Node.js middleware |
| `startup-flow.md` | Outdated - references removed components |

For current setup instructions, see the [canton-middleware Setup Guide](https://github.com/ChainSafe/canton-middleware/blob/main/docs/SETUP_AND_TESTING.md).
