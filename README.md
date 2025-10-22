# Canton ERC-20 Vertical Slice

This repo contains a Daml-based ERC‑20 example, a Node.js indexer, and a gRPC middleware prototype. Use the documents below to prepare your environment and launch the stack.

## Documentation

- [`docs/dev-setup.md`](docs/dev-setup.md) – prerequisites and installation steps for macOS & Linux.
- [`docs/startup-flow.md`](docs/startup-flow.md) – step-by-step startup guide (sandbox, JSON API, indexer, middleware).
- [`daml/instructions.md`](daml/instructions.md) – JSON API walkthrough (mint, transfer, balance checks).
- [`docs/Plan.md`](docs/Plan.md) – high-level architecture & roadmap.

## Repo Structure

```
canton-ERC20/
├─ daml/              # ERC-20 Daml code and scripts
├─ scripts/           # bootstrap helpers (sandbox + JSON API)
├─ indexer/           # Node.js indexer (REST facade over ledger state)
├─ middleware/        # Node.js gRPC middleware (BalanceOf/TotalSupply/Allowance)
├─ docs/              # design & setup documentation
└─ json-api.conf      # JSON API configuration (auth + token settings)
```

## Quick Start

```bash
./scripts/bootstrap.sh      # build DAR, start sandbox, start JSON API
source dev-env.sh           # load helper exports (tokens, IDs, ports)

cd indexer && npm install && npm start
cd ../middleware && npm install && npm start
```

Check `docs/startup-flow.md` for detailed verification steps and troubleshooting tips.
