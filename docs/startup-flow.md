# Startup Flow (Vertical Slice)

This guide walks through bringing up the Canton ERC‑20 sample stack using the helper scripts, Go indexer, and Node.js middleware. It assumes you have completed the tool installation described in [dev-setup.md](./dev-setup.md).

## Components Overview

| Component | Location | Purpose |
| --------- | -------- | ------- |
| Daml Sandbox & Scripts | `scripts/bootstrap.sh`, `daml/` | Runs the ledger, uploads the ERC‑20 DAR, and seeds sample data. |
| Go Indexer | `indexer-go/` | Connects to the Ledger gRPC API and maintains balances/allowances in memory. |
| Middleware (gRPC) | `middleware/` | Vertical slice server that maps gRPC requests to indexer queries. |

## 1. Bootstrap the Ledger

```bash
./scripts/bootstrap.sh
```

The script is idempotent:
- builds the DAR in `daml/`;
- starts or reuses the sandbox on `${SANDBOX_PORT:-6865}`;
- uploads the DAR and runs the bootstrap scripts (`ERC20.Script:test`, `ERC20.Inspect:balancesOk`);
- allocates Issuer/Alice/Bob on the ledger;
- writes helper exports (package id, party ids, etc.) to `dev-env.sh`.

## 2. Load Environment Exports

In every terminal where you interact with the stack:

```bash
source dev-env.sh
```

This exposes:

```
LEDGER_ID, SANDBOX_PORT
ERC20_PKG_ID, ISSUER_PARTY, ALICE_PARTY, BOB_PARTY
```

The indexer and middleware pick up these variables automatically.

## 3. Start the Go Indexer

```bash
source dev-env.sh
export INDEXER_PARTY=$ISSUER_PARTY
cd indexer-go
./scripts/gen-ledger.sh   # requires protoc + protoc-gen-go
go mod tidy               # fetch dependencies (requires network connectivity)
GOMODCACHE=$(pwd)/.gomodcache GOCACHE=$(pwd)/.gocache go run ./cmd/indexer
```

The indexer connects to the Ledger gRPC endpoint and exposes REST endpoints on `${PORT:-9000}` (`/healthz`, `/balanceOf`, `/allowance`, `/totalSupply`, `/state`). Example queries:

```bash
curl "http://localhost:9000/balanceOf?party=$ALICE_PARTY"
curl "http://localhost:9000/allowance?owner=$ALICE_PARTY&spender=$BOB_PARTY"
curl "http://localhost:9000/totalSupply"
```

## 4. Start the Middleware (gRPC)

```bash
cd middleware
npm install          # first run only
npm start
```

The middleware listens on `${PORT:-50051}` and calls the indexer REST endpoints. The vertical slice supports `BalanceOf`, `TotalSupply`, and `Allowance`. Because reflection is not enabled, point `grpcurl` at the bundled proto:

```bash
grpcurl -plaintext \
  -import-path middleware/proto \
  -proto erc20.proto \
  -d '{"token":{"symbol":"CCN"},"owner":{"party":"'"$ALICE_PARTY"'"}}' \
  localhost:50051 canton.erc20.v1.ERC20Service/BalanceOf

grpcurl -plaintext \
  -import-path middleware/proto \
  -proto erc20.proto \
  -d '{"token":{"symbol":"CCN"}}' \
  localhost:50051 canton.erc20.v1.ERC20Service/TotalSupply

grpcurl -plaintext \
  -import-path middleware/proto \
  -proto erc20.proto \
  -d '{"token":{"symbol":"CCN"},"owner":{"party":"'"$ALICE_PARTY"'"},"spender":{"party":"'"$BOB_PARTY"'"}}' \
  localhost:50051 canton.erc20.v1.ERC20Service/Allowance
```

## 5. Shutdown

- Ctrl+C in the indexer and middleware terminals.
- To stop the sandbox started by `bootstrap.sh`, terminate the process recorded in `log/sandbox-bootstrap.pid`, or simply close the terminal session that launched it.

## Troubleshooting

| Symptom | Likely Cause / Fix |
| ------- | ------------------ |
| `ERC20_PKG_ID` or `INDEXER_PARTY` missing | `source dev-env.sh` (and export `INDEXER_PARTY=$ISSUER_PARTY`). |
| Ledger connection refused | Ensure the sandbox is running (`./scripts/bootstrap.sh`). |
| `CONTRACT_NOT_FOUND` when exercising transfers twice | The previous transfer archived the holding. Re-run the query in §3.4 to fetch the latest holding CID before submitting again. |

---

You are now ready to extend the indexer (e.g. add persistence) or flesh out additional middleware RPCs.
