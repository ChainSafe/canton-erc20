# Go Indexer (Ledger gRPC)

This module provides an indexer implementation in Go that connects directly to the Canton Ledger API (gRPC) instead of the JSON API. It builds an in-memory projection of ERC-20 holdings and allowances and exposes REST endpoints for queries.

## Prerequisites

- Go 1.21+
- `protoc` 3.21+
- Go protobuf plugins:
  ```bash
  go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
  go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
  ```
- Daml SDK (for running the sandbox & scripts as documented in `../docs/startup-flow.md`)

## Generate gRPC stubs

The necessary ledger API `.proto` files are extracted under `proto/`. Generate Go stubs once (or when upgrading the SDK):

```bash
cd canton-erc20/indexer-go
./scripts/gen-ledger.sh
go mod tidy
```

The generated files are written to `gen/`.

## Configuration

Environment variables (defaults in brackets):

| Variable          | Description                                                   |
|-------------------|---------------------------------------------------------------|
| `LEDGER_ADDRESS`  | Ledger gRPC endpoint (`127.0.0.1:6865`)                       |
| `LEDGER_ID`       | Ledger identifier (`sandbox`)                                 |
| `ERC20_PKG_ID`    | **Required** ERC-20 package ID (exported by `bootstrap.sh`)   |
| `INDEXER_PARTY`   | **Required** Party used for subscription (e.g. issuer)        |
| `TOKEN_SYMBOL`    | Default token symbol (`CCN`)                                  |
| `PORT`            | HTTP port for REST API (`9000`)                               |

When you run `./scripts/bootstrap.sh`, `dev-env.sh` exports `ERC20_PKG_ID`, `ISSUER_PARTY`, etc. Source it before starting:

```bash
source ../dev-env.sh
export INDEXER_PARTY=$ISSUER_PARTY
cd indexer-go
./scripts/gen-ledger.sh   # one-time
go mod tidy               # ensure dependencies are fetched
go run ./cmd/indexer
```

## REST Endpoints

Served on `http://localhost:${PORT}`:

- `GET /healthz`
- `GET /balanceOf?party=<party>&symbol=CCN`
- `GET /allowance?owner=<party>&spender=<party>&symbol=CCN`
- `GET /totalSupply?symbol=CCN`
- `GET /state` – debug snapshot

## Architecture Notes

- Uses `ActiveContractsService/GetActiveContracts` for the initial snapshot and `TransactionService/GetTransactions` for the live stream.
- Currently supports plaintext (insecure) gRPC connections for local development; extend `ledgerclient.Config` to use TLS in production.
- Stores holdings/allowances in-memory; follow-up work should persist them to Postgres and expose gRPC/REST endpoints behind authentication.
