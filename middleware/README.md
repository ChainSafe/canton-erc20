# ERC-20 Middleware

This module exposes a gRPC service that maps ERC‑20 semantics onto Canton smart contracts.  The service consumes the `proto/erc20.proto` definition and should be implemented in the language of choice (Go, Rust, TypeScript, …) using the following responsibilities:

- **Command Orchestrator** – submits Canton ledger commands for `transfer`, `approve`, `transferFrom`, `mint`, and `burn` using the Ledger API v1/v2.
- **Indexer Adapter** – reads balances, allowances, and total supply from the indexer’s query API instead of the ledger for low-latency responses.
- **Identity & Authorization** – validates client credentials (JWT/OIDC) and maps external account identifiers to Canton parties.

## Quick Start (vertical slice)

Install dependencies:

```bash
cd middleware
npm install
```

Run the server (assumes the indexer HTTP API is listening on `localhost:9000`):

```bash
source ../dev-env.sh \
INDEXER_BASE_URL=${INDEXER_BASE_URL:-http://localhost:9000} \
PORT=50051 \
npm start
```

Call the RPCs using `grpcurl` (reflection is disabled, so pass the proto file):

```bash
grpcurl -plaintext \
  -import-path proto \
  -proto erc20.proto \
  -d '{"token":{"symbol":"CCN"},"owner":{"party":"alice::...your-party..."}}' \
  localhost:50051 canton.erc20.v1.ERC20Service/BalanceOf

grpcurl -plaintext \
  -import-path proto \
  -proto erc20.proto \
  -d '{"token":{"symbol":"CCN"}}' \
  localhost:50051 canton.erc20.v1.ERC20Service/TotalSupply

grpcurl -plaintext \
  -import-path proto \
  -proto erc20.proto \
  -d '{"token":{"symbol":"CCN"},"owner":{"party":"alice::...your-party..."},"spender":{"party":"bob::...your-party..."}}' \
  localhost:50051 canton.erc20.v1.ERC20Service/Allowance
```

`BalanceOf`, `TotalSupply`, and `Allowance` proxy through the indexer. Mutating calls (`Transfer`, `Approve`, etc.) remain `UNIMPLEMENTED` in the vertical slice.

## Generating gRPC Stubs

When you expand beyond the prototype, generate stubs in your implementation language. Example (Go):

```bash
protoc \
  --go_out=./gen --go_opt=paths=source_relative \
  --go-grpc_out=./gen --go-grpc_opt=paths=source_relative \
  proto/erc20.proto
```

## Folder Layout

```
middleware/
├─ proto/
│   └─ erc20.proto          # gRPC definition
├─ index.js                 # Node.js gRPC server (BalanceOf only)
├─ package.json             # dependencies & scripts
└─ README.md                # this file
```

Implementors should follow the architecture documented in `docs/architecture/diagram.md` and use the indexer (see `../indexer/`) for all read-heavy queries. As you flesh out additional ERC-20 functions, the middleware should submit ledger commands and rely on the indexer for read operations.
