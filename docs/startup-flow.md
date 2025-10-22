# Startup Flow (Vertical Slice)

This guide walks through bringing up the Canton ERC‑20 sample stack using the helper scripts and Node indexer. It assumes you have completed the tool installation described in [dev-setup.md](./dev-setup.md).

## Components Overview

| Component | Location | Purpose |
| --------- | -------- | ------- |
| Daml Sandbox & Scripts | `scripts/bootstrap.sh`, `daml/` | Runs the ledger, uploads the ERC‑20 DAR, and seeds sample data. |
| JSON API | `json-api.conf` | REST/stream gateway used by the indexer and manual curl commands. |
| Node Indexer | `indexer/` | Reads holdings/allowances from the JSON API and exposes REST endpoints for the middleware. |
| Middleware (gRPC) | `middleware/` | Vertical slice server that maps gRPC requests to indexer queries (BalanceOf implemented). |

## 1. Bootstrap the Ledger & JSON API

```bash
cd canton-ERC20
./scripts/bootstrap.sh
```

The script is idempotent:
- builds the DAR in `daml/`;
- starts or reuses the sandbox on `${SANDBOX_PORT:-6865}`;
- uploads the DAR and runs the bootstrap scripts (`ERC20.Script:test`, `ERC20.Inspect:balancesOk`);
- allocates Issuer/Alice/Bob on the ledger;
- starts or reuses the JSON API on `${JSON_API_PORT:-7575}` using `json-api.conf`;
- writes helper exports (package id, party ids, JWTs, etc.) to `dev-env.sh`.

## 2. Load Environment Exports

In every terminal where you interact with the stack:

```bash
cd canton-ERC20
source dev-env.sh
```

This exposes:

```
LEDGER_ID, SANDBOX_PORT, JSON_API_PORT, DEV_SECRET
ERC20_PKG_ID, ISSUER_PARTY, ALICE_PARTY, BOB_PARTY
TOKEN_ISSUER, TOKEN_ALICE, TOKEN_BOB, TOKEN_ISSUER_ALICE
```

The indexer and middleware pick up these variables automatically.

## 3. Start the Indexer

```bash
cd canton-ERC20/indexer
npm install          # first run only
npm start
```

Behaviour:
- pulls the initial snapshot from `/v1/query`;
- attempts to stream updates from `/v1/stream/query`; if unavailable, falls back to polling every `POLL_INTERVAL_MS` (default 5s);
- exposes REST endpoints on `${PORT:-9000}` (`/healthz`, `/balanceOf`, `/allowance`, `/totalSupply`, `/state`).

Sample queries:

```bash
curl "http://localhost:9000/balanceOf?party=$ALICE_PARTY"
curl "http://localhost:9000/allowance?owner=$ALICE_PARTY&spender=$BOB_PARTY"
curl "http://localhost:9000/totalSupply"
```

## 4. Start the Middleware (gRPC)

```bash
cd canton-ERC20/middleware
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

## 5. Manual JSON API Checks (Optional)

Use the exported tokens to interact with the ledger directly:

```bash
# List token managers visible to the issuer
curl -s http://127.0.0.1:${JSON_API_PORT}/v1/query \
  -H "Authorization: Bearer $TOKEN_ISSUER" \
  -H "Content-type: application/json" \
  -d "{\"templateIds\":[\"$ERC20_PKG_ID:ERC20.Token:TokenManager\"],\"query\":{}}" | jq

# Mint additional CCN to Alice
curl -s http://127.0.0.1:${JSON_API_PORT}/v1/exercise \
  -H "Authorization: Bearer $TOKEN_ISSUER" \
  -H "Content-type: application/json" \
  -d "{
        \"templateId\":\"$ERC20_PKG_ID:ERC20.Token:TokenManager\",
        \"contractId\":\"$TM_CID\",
        \"choice\":\"Mint\",
        \"argument\":{\"to\":\"$ALICE_PARTY\",\"amount\":50.0}
      }" | jq
```

Refer to `daml/instructions.md` for a full catalogue of JSON API examples.

## 6. Shutdown

- Ctrl+C in the indexer and middleware terminals.
- To stop the sandbox/JSON API started by `bootstrap.sh`, terminate the processes recorded in `log/sandbox-bootstrap.pid` and `log/json-api-bootstrap.pid`, or simply close the terminal session that launched them.

## Troubleshooting

| Symptom | Likely Cause / Fix |
| ------- | ------------------ |
| `ERC20_PKG_ID environment variable is required` | `source dev-env.sh` in the terminal that runs the service. |
| `401 Unauthorized` from JSON API | `dev-env.sh` not sourced or token expired. Set `JSON_API_TOKEN="Bearer $TOKEN_ISSUER"` before starting the indexer/middleware. |
| Streaming errors (HTTP 400 on `/v1/stream/query`) | JSON API query store not enabled. The indexer automatically falls back to polling; no action required, or enable query-store if you need streaming. |
| `CONTRACT_NOT_FOUND` when exercising transfers twice | The previous transfer archived the holding. Re-run the query in §3.4 to fetch the latest holding CID before submitting again. |

---

You are now ready to extend the indexer (e.g. add persistence) or flesh out additional middleware RPCs.
