# Canton ERC-20

This repo contains a Daml-based ERC‑20 example, a Go-based indexer (Ledger gRPC), and a Node.js gRPC middleware. Use the documents below to prepare your environment and launch the stack.

## Documentation

- [`docs/dev-setup.md`](docs/dev-setup.md) – prerequisites and installation steps for macOS & Linux.
- [`docs/startup-flow.md`](docs/startup-flow.md) – step-by-step startup guide (sandbox, Go indexer, middleware).
- [`daml/instructions.md`](daml/instructions.md) – ledger walkthrough (mint, transfer, balance checks).
- [`docs/Plan.md`](docs/Plan.md) – high-level architecture & roadmap.

## Repo Structure

```
canton-ERC20/
├─ daml/              # ERC-20 Daml code and scripts
├─ scripts/           # bootstrap helpers (sandbox)
├─ indexer-go/        # Go indexer consuming the Ledger gRPC API
├─ middleware/        # Node.js gRPC middleware (BalanceOf/TotalSupply/Allowance)
├─ docs/              # design & setup documentation
└─ dev-env.sh         # generated environment exports (after bootstrap)
```

## Quick Start

```bash
./scripts/bootstrap.sh      # build DAR, start sandbox, seed ledger
source dev-env.sh           # load helper exports (package id, parties)

# Go indexer (Ledger gRPC)
cd indexer-go
./scripts/gen-ledger.sh     # generate gRPC stubs (requires protoc-gen-go)
go mod tidy                 # downloads Go dependencies (requires network)
export INDEXER_PARTY=$ISSUER_PARTY
GOMODCACHE=$(pwd)/.gomodcache GOCACHE=$(pwd)/.gocache go run ./cmd/indexer   # REST API on http://localhost:9000

# Middleware
cd ../middleware
npm install
npm start
```

Check `docs/startup-flow.md` for detailed verification steps and troubleshooting tips.
