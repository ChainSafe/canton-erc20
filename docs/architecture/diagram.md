### Component Overview

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
|  • gRPC (or REST) API exposing ERC-20 semantics              |
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
|  • Read API (REST/gRPC) for middleware & downstream tools    |
+---------------------------▲----------------------------------+
                            |
                            |  Active Contracts & Updates      |
                            ▼
+--------------------------------------------------------------+
|                  Canton Ledger / Participant Node            |
|  • Daml Templates (TokenManager, TokenHolding, Allowance)    |
|  • Canton GDP + Ledger API                                   |
|  • Party Identity Management                                 |
+--------------------------------------------------------------+
```

### Component Responsibilities

1. **Canton Ledger / Participant Node**  
   - Hosts the Daml smart contracts that implement CIP‑56 compliant token logic.  
   - Enforces transaction authorization, privacy, and contract invariants.  
   - Exposes the Ledger API (gRPC) that both middleware and indexer use.

2. **Indexer Service**  
   - Subscribes to `GetActiveContracts` and `GetTransactions` streams to build a canonical read model.  
   - Persists holdings, allowances, and total supply in Postgres.  
   - Provides a lightweight query API (REST/gRPC) for balanceOf, allowance, and totalSupply requests.  
   - Supplies offsets/checkpointing so it can recover after restarts without replaying the entire ledger.

3. **ERC‑20 Middleware**  
   - Exposes a developer-friendly ERC‑20 interface (transfer, approve, transferFrom, etc.).  
   - Issues ledger commands using callers’ Canton party credentials.  
   - Reads from the indexer instead of the ledger for low-latency balance queries.  
   - Handles authentication/authorization (JWT/OIDC) and party resolution (Ethereum-style addresses → Canton parties).  

4. **Client Applications**  
   - Internal services, wallets, dashboards or third-party integrations that act as ERC‑20 clients.  
   - Communicate with the middleware via gRPC (preferred) or REST.

### End-to-End Flow (Transfer Example)

```text
Client → Middleware → Ledger → Indexer → Middleware → Client
   |        |            |           |           |         |
   | 1. transfer()       |           |           |         |
   |        |            | 2. Submit ledger command        |
   |        |            |           |           |         |
   |        |            |           | 3. Stream update     |
   |        |            |           |    (created/archived)|
   |        |            |           |           |         |
   |        | 4. read balance from indexer       |         |
   |        |            |           |           |         |
   | 5. response ------------------------------------------------→ |
```

1. Client calls `transfer(from, to, amount)` on the middleware.  
2. Middleware constructs a Daml command (using the caller’s party credentials) and submits it via the Ledger API.  
3. Canton executes the transaction, emitting create/archive events the indexer observes.  
4. The indexer updates its Postgres projections; the middleware reads the new balance when replying.  
5. Client receives confirmation with updated state.

### Notes & Future Extensions

- **Privacy Modes**: Middleware and indexer can run in global visibility (e.g., Canton Coin SV) or scoped visibility (issuer/user-specific). Authorization logic in the middleware restricts what data is returned.  
- **Multi-Token Support**: In Phase 2 we will introduce Daml interfaces and runtime configuration so the middleware can support any token implementing the ERC‑20 compatibility interface.  
- **Governance**: Phase 3 involves proposing a CIP so Canton Coin implements the interface natively and Super Validators can run the middleware/indexer as shared infrastructure.  
- **Operations**: Containerize each component, provide Helm charts, metrics (Prometheus), and CI pipelines to build/test/deploy.
