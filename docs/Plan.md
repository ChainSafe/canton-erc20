
---
# 1. Architecture Overview
```text
+--------------------------------------------------------------+
|                       Client Applications                    |
|   (internal services, wallets, dashboards, middleware APIs)  |
+---------------------------▲----------------------------------+
                            |
                            |  Read/Write (REST/gRPC)
                            ▼
+--------------------------------------------------------------+
|                 ERC-20 Middleware (Service Layer)            |
|  • gRPC API exposing ERC-20 semantics                        |
|  • Command Orchestrator (executes transfers/mints via ledger)|
|  • Indexer Adapter (reads balance/allowance from indexer)    |
|  • Identity & Auth (Canton parties, JWT/OIDC integration)    |
+---------------------------▲----------------------------------+
                            |
                            |  Queries / Events (gRPC)
                            ▼
+--------------------------------------------------------------+
|                     Indexer Service                          |
|  • Ledger Connector (ActiveContracts + Transactions stream)  |
|  • State Processor (builds balance, allowance, supply views) |
|  • Persistence (Postgres schema + change tracking)           |
|  • Read API (gRPC) for middleware & downstream tools         |
+---------------------------▲----------------------------------+
                            |
                            |  Active Contracts & Updates      |
                            ▼
+--------------------------------------------------------------+
|                  Canton Ledger (DAML) / Participant Node     |
|  • Daml Templates (TokenManager, TokenHolding, Allowance)    |
|  • Canton GDP + Ledger API                                   |
|  • Party Identity Management                                 |
+--------------------------------------------------------------+
```

- The dashed lines represent how information flows. 
- The ledger is the source of truth; the indexer consumes contract events, keeps a canonical read model in Postgres (balances, allowances, total supply), and exposes a read-only API. 
- The middleware exposes ERC-20 semantics and translates requests into ledger writes plus read queries against the indexer.

---
# 2. DAML Layer

- TokenManager template – signatory: issuer; choices: Mint, Burn.
- TokenHolding template – signatory: issuer; observer: owner; choice: Transfer (controller = owner).
- Allowance template – signatory: issuer and owner; observer: spender; choices: Approve, Decrease, Use.
- Interface definitions in Phase 2 (ERC20Compatible).
- We should align with CIP-56

Deliverables: compile to DAR, script tests to seed and inspect, docs explaining ledger invariants (no double-spend, minted tokens tracked, roles enforced).'

---
# 3. Indexer Service

- Production-ready baseline focused on resiliency, persistence, and observability.
- **Ledger connectivity**
  - Replace JSON API dependency with gRPC Ledger API (`GetActiveContracts`, `GetTransactions`).
  - Support TLS / mTLS and authenticated service users (API tokens or client certs).
  - Handle reconnect/backoff, heartbeat detection, and restart from stored offsets.
  - Optional: multi-domain support (track offsets per domain).
- **Visibility & multi-party**
  - Ensure the indexer party is granted observer rights or receives aggregated reporting contracts.
  - Support multiple issuers / tokens via inclusive filters or per-token configuration.
- **Persistence layer**
  - Backed by Postgres (or CockroachDB) using the schema below.
  - Store last processed offset to guarantee idempotent recovery.
  - Consider partitioning holdings/allowances tables by token_id for large datasets.

```sql
CREATE TABLE tokens (
  token_id SERIAL PRIMARY KEY,
  symbol TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  decimals INT NOT NULL,
  issuer_party TEXT NOT NULL,
  active BOOLEAN DEFAULT TRUE,
  metadata JSONB DEFAULT '{}'
);

CREATE TABLE holdings (
  contract_id TEXT PRIMARY KEY,
  token_id INT REFERENCES tokens(token_id),
  owner_party TEXT NOT NULL,
  amount NUMERIC NOT NULL,
  last_update TIMESTAMP NOT NULL DEFAULT now(),
  archived BOOLEAN DEFAULT FALSE,
  event_offset TEXT NOT NULL
);

CREATE TABLE allowances (
  contract_id TEXT PRIMARY KEY,
  token_id INT REFERENCES tokens(token_id),
  owner_party TEXT NOT NULL,
  spender_party TEXT NOT NULL,
  amount NUMERIC NOT NULL,
  last_update TIMESTAMP NOT NULL DEFAULT now(),
  archived BOOLEAN DEFAULT FALSE,
  event_offset TEXT NOT NULL
);

CREATE TABLE indexer_offsets (
  consumer_name TEXT PRIMARY KEY,
  last_offset TEXT NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE VIEW balances AS
SELECT token_id, owner_party, SUM(amount) AS balance
FROM holdings
WHERE archived = FALSE
GROUP BY 1,2;

CREATE VIEW total_supply AS
SELECT token_id, SUM(amount) AS supply
FROM holdings
WHERE archived = FALSE
GROUP BY 1;
```

- **API surface**
  - REST/gRPC read APIs (`balanceOf`, `allowance`, `totalSupply`, token metadata).
  - Low-latency queries with optional pagination and caching.
  - Authentication/authorization for downstream consumers (mTLS or signed JWTs).
- **Performance & ops**
  - Batch upserts, tune DB connections, support read replicas.
  - Emit metrics (ledger lag, events per second, DB latency) and structured logs.
  - Package as a Go/Rust binary (or hardened Node service) with helm/Terraform deployment artefacts.
  - Provide disaster recovery via snapshot replay and automated catch-up testing.

``` sql
CREATE TABLE tokens (
  token_id SERIAL PRIMARY KEY,
  symbol TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  decimals INT NOT NULL,
  issuer_party TEXT NOT NULL
);

CREATE TABLE holdings (
  contract_id TEXT PRIMARY KEY,
  token_id INT REFERENCES tokens(token_id),
  owner_party TEXT NOT NULL,
  amount NUMERIC NOT NULL, -- stored as decimal
  last_update TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE allowances (
  contract_id TEXT PRIMARY KEY,
  token_id INT REFERENCES tokens(token_id),
  owner_party TEXT NOT NULL,
  spender_party TEXT NOT NULL,
  amount NUMERIC NOT NULL,
  last_update TIMESTAMP NOT NULL DEFAULT now()
);

CREATE VIEW balances AS
SELECT
  token_id,
  owner_party,
  SUM(amount) AS balance
FROM holdings
GROUP BY 1,2;

CREATE VIEW total_supply AS
SELECT token_id, SUM(amount) AS supply
FROM holdings
GROUP BY 1;
```

- API: either REST (Express/FastAPI) or gRPC:
  - GET /balance/:token/:party
  - GET /allowance/:token/:owner/:spender
  - GET /totalSupply/:token
  - GET /tokenMetadata/:token
- Authentication: only allow requests from middleware (or implement per-party authorization).
- Resilience: store last processed offset; on restart, resume from last offset (via transaction stream parameter begin offset). Ensure idempotent updates by keying rows by contract_id.

---
# 4. Middleware Service

- gRPC interface definitions (proto) for ERC-20 functions:

```proto 

service ERC20 {
  rpc BalanceOf (BalanceRequest) returns (BalanceReply);
  rpc TotalSupply (TotalSupplyRequest) returns (TotalSupplyReply);
  rpc Transfer (TransferRequest) returns (TransferReply);
  rpc Approve (ApproveRequest) returns (ApproveReply);
  rpc TransferFrom (TransferFromRequest) returns (TransferFromReply);
  rpc Allowance (AllowanceRequest) returns (AllowanceReply);
}
```

- **Implementation goals**
  - `BalanceOf`, `Allowance`, `TotalSupply`: query the indexer with caching/hedging for low latency.
  - `Transfer`, `Mint`, `Burn`, `Approve`, `TransferFrom`: submit Canton commands with deduplication IDs, retries, and idempotency.
  - Perform UTXO selection to aggregate holdings when necessary; consider aggregator templates.
  - Support multi-token context in all requests and tie to token metadata.
  - Integrate identity/auth (OIDC/JWT) to map external users to Canton parties.
  - Implement rate limiting, quotas, and auditing for commands.
  - Emit Prometheus metrics (request latency, command success/failure, submission lag).
- **Resilience & ops**
  - Circuit breakers for indexer/ledger dependencies.
  - Configurable timeouts and retries on gRPC errors.
  - Structured logging with Canton correlation IDs.
- **Test strategy**
  - Integration tests covering happy paths and failure modes (insufficient balance, allowance exceeded).
  - End-to-end flows (mint → transfer → query) with deterministic assertions.
  - Mocking/indexer stubs for unit tests.


---
# 5. Deployment & DevOps

- Containerization: multi-stage Dockerfiles for indexer & middleware; pinned base images.
- Local stack: docker-compose with Canton participant, JSON API, Postgres, indexer, middleware.
- Production IaC: Helm charts / Terraform for participant onboarding, database provisioning, app deployment.
- Secrets management: integrate with Vault / AWS Secrets Manager for API tokens, DB creds.
- CI/CD pipeline:
  - lint/format (Daml, Go/Node),
  - unit tests + integration tests,
  - Daml build and compatibility checks,
  - container build + security scan,
  - helm chart packaging and promotion.
- Observability:
  - Metrics (offset lag, command latency, API QPS),
  - Distributed tracing (OpenTelemetry) spanning middleware → indexer → Canton,
  - Structured logging (JSON) with correlation IDs.
- Alerting on lag thresholds, error rates, DB replication issues, token supply anomalies.

Example sequence diagram for transfer:

1. Client → middleware: transfer(from, to, amount)
2. Middleware resolves parties, selects holdings, constructs ledger command.
3. Middleware → ledger (gRPC CommandService): SubmitTransfer.
4. Ledger executes, emits create/arch events.
5. Indexer (listening) updates DB.
6. Client queries balanceOf → middleware → indexer (DB) → returns new balance.

---
# 6. Project Structure Example

```text
repo/
├─ daml/
│   ├─ daml.yaml
│   └─ ERC20/*.daml
├─ indexer/
│   ├─ src/ (Node)
│   ├─ migrations/...
│   ├─ Dockerfile
│   └─ README.md
├─ middleware/
│   ├─ src/
│   ├─ proto/erc20.proto
│   ├─ Dockerfile
│   └─ README.md
├─ docs/
│   ├─ architecture/
│   │   ├─ component-diagram.png
│   │   ├─ sequence-transfer.png
│   │   └─ readme.md
│   └─ operations/
├─ docker-compose.yml
 9└─ README.md
```
---
# 7. Phased Implementation Plan

1. **Ledger & Daml** – finalize templates, invariants, scripts; document party topology.
2. **Indexer Phase 1** – gRPC connector, Postgres persistence, read API, JSON API fallback for dev.
3. **Middleware Phase 1** – gRPC ERC‑20 interface, BalanceOf/Totals wired to indexer, command submission skeleton.
4. **Security Hardening** – TLS/mTLS, service identities, OIDC/JWT integration, RBAC.
5. **Indexer Phase 2** – advanced projections (history tables), caching, scaling strategies, multi-domain support.
6. **Middleware Phase 2** – full command coverage (TransferFrom, Approve, Burn), idempotent workflows, UTXO selection, retries.
7. **Ops & DevEx** – Docker/Helm, monitoring, logging, alerting, CI/CD automation, automated migrations.
8. **Scalability & Governance** – multi-token/multi-tenant readiness, read replicas, sharding, runbooks, SLA definition, audit logging.

---
# 8. Documentation & Governance

- Provide architecture doc with:
  - component diagram, sequence diagrams, API specs.
  - data model explanation.
  - mapping to CIP requirements (e.g., CIP-56 compliance).
- Add contributions for governance CIP (Phase 3): CIP document in CIP format, test plan summary, adoption plan (adding ChainSafe as SV etc).
- Reference Dfns integration approach to justify security choices (KMS, MPC).

# 9. Next Steps

- Solidify Daml template & script (you already have; ensure they match CIP-56 semantics).
- Choose indexer language (Go or Rust recommended). Build gRPC client, Postgres persistence.
- Define proto for middleware & stub endpoints.
- Set up repository with structure above; include precise README instructions (how to run full stack locally via docker-compose).
- Implement unit/integration tests for indexer and middleware.
- Document architecture & design decisions in docs/ folder.
