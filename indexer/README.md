# Indexer Service

The indexer ingests Canton ledger events (TokenHolding / Allowance contracts) and materialises an ERC‑20 friendly read model in Postgres.

## Directory Layout

```
indexer/
├─ src/                # place service implementation here
├─ migrations/         # SQL migrations for Postgres
│   └─ 001_create_token_tables.sql
├─ package.json        # optional Node.js starter (can be replaced with Go/Rust)
└─ README.md
```

## Database Setup

Apply the SQL migrations (in order) before running the service:

```bash
psql $DATABASE_URL -f migrations/001_create_token_tables.sql
```

The schema creates:
- `tokens` – registry of supported tokens (symbol, metadata, issuer party).
- `holdings` – active holdings per token contract (one row per TokenHolding).
- `allowances` – active allowances (one row per Allowance contract).
- `balances` / `total_supply` views – convenience projections used by the middleware.

## Ingestion Pipeline (high level)

1. Connect to the Canton Ledger API (`ActiveContractsService` & `TransactionService`).
2. Load the initial snapshot of `TokenHolding` and `Allowance` contracts visible to the indexer party.
3. Stream new transactions from the recorded offset, upserting rows using `contract_id` as the primary key.
4. Expose read APIs (REST/gRPC) so the middleware can serve `balanceOf`, `allowance`, and `totalSupply` requests without querying the ledger directly.

For the vertical slice in this repository, a lightweight in-memory projection served via Express is available (`index.js`). Run:

```bash
npm install        # install dependencies (first run)
source ../dev-env.sh   # exported by scripts/bootstrap.sh
cd indexer
npm start
```

Environment variables:

- `JSON_API` – JSON API base URL (defaults to `http://127.0.0.1:7575`).
- `JSON_API_TOKEN` / `TOKEN_ISSUER` – bearer token for authenticated JSON API instances (`dev-env.sh` exports one by default).
- `PORT` – indexer HTTP port (`9000` by default).
- `TOKEN_SYMBOL` – default token symbol (`CCN`).
- `ERC20_PKG_ID` – **required**. The ERC-20 package hash (see `dev-env.sh`).
- `DISABLE_STREAM` – set to `1` to skip the JSON API streaming endpoint.
- `POLL_INTERVAL_MS` – refresh interval when polling fallback is in use (default `5000`).

Endpoints:

- `GET /healthz` – basic health probe.
- `GET /balanceOf?party=<party-id>&symbol=CCN`
- `GET /totalSupply?symbol=CCN`
- `GET /allowance?owner=<party-id>&spender=<party-id>&symbol=CCN`
- `GET /state` – debugging snapshot of the in-memory projection.

This mode reads holdings/allowances from the Canton JSON API. If the `/v1/stream/query` endpoint is unavailable (requires the JSON API query-store module), the indexer automatically falls back to polling `/v1/query` every `POLL_INTERVAL_MS`. Once you move to production, switch to the gRPC Ledger API and persist state in Postgres using the migrations above.

See `docs/architecture/diagram.md` for the full component architecture.
