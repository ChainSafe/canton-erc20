# Daml Middleware Bridge Architecture

This document specifies how to build and operate a production-grade middleware bridge for Daml applications. It focuses on repository governance, ledger-facing design patterns, middleware integration, validation, and Canton operations, using this repo’s ERC-20 implementation as the reference point.

## 1. Why the Bridge Matters
- The bridge is the translation layer between deterministic on-ledger logic and non-deterministic off-ledger systems (APIs, UIs, databases).
- It must uphold bilateral consent on-ledger while offering a familiar developer surface (e.g., ERC-20 semantics) off-ledger.
- Correctness depends on aligning Daml templates, generated bindings, middleware code, and infrastructure in a single coherent lifecycle.

## 2. Repository Architecture & Governance
- **Monorepo rationale:** Daml templates are the type-level contract for all generated bindings. Keeping ledger code, generated codegen, middleware, UI, and ops scripts in one repo enforces atomic commits and prevents integration drift.
- **Current layout (authoritative paths):**
  - `daml/` – on-ledger model (`daml.yaml`, `daml.lock`, sources under `ERC20/`).
  - `middleware/` – Node.js gRPC/REST bridge for ERC-20 commands.
  - `indexer-go/` – Go indexer consuming Ledger gRPC to project balances/allowances.
  - `docs/` – design, setup, and architecture notes (this file).
  - `scripts/` – bootstrap helpers (sandbox startup, environment exports).
- **Workspace coordination:** Introduce `multi-package.yaml` at the repo root once multiple Daml packages are added; only packages listed there are rebuilt by `daml build`.
- **Per-package config (`daml.yaml`):**
  - Standard dependencies: `daml-prim`, `daml-stdlib`, `daml-script`.
  - Data-dependencies: reference sibling DARs via relative paths, e.g.:
    ```yaml
    data-dependencies:
      - ../common-types/.daml/dist/common-types-1.0.0.dar
    ```
  - Commit `daml.lock` to pin package IDs and guarantee reproducible builds across dev and CI.
- **Organizational mirroring:** Repo structure mirrors roles (ledger, middleware, infra, UI) but keeps visibility permeable so bridge engineers can inspect infra (`ops/canton.conf`) when diagnosing connectivity.

## 3. Ledger Design Patterns for the Bridge
- **Propose & Accept (onboarding handshake):**
  ```haskell
  template UserInvitation
    with operator : Party; username : Party
    where
      signatory operator
      observer username

      choice AcceptInvitation : ContractId User
        with initialProfile : Text
        controller username
        do create User with operator; username; profileData = initialProfile
  ```
  - The middleware (acting as `operator`) creates the invitation; the end user supplies the second signature by exercising `AcceptInvitation`, preventing forged onboarding.
- **Modular proposals:** Generalize invitations into reusable proposal/response templates so middleware handles one pattern instead of bespoke flows per use case.
- **Contention management:** Avoid hotspots by keeping per-entity contracts (one `User`/`Holding` per party), prefer non-consuming choices for shared config, and partition along natural boundaries (token, region, tenant) to limit MVCC conflicts.
- **Data factoring:** Use record types (e.g., `UserProfile`) for clarity and reuse. Updates must rebuild the record when nested fields change, trading verbosity for stronger typing.

## 4. Middleware Integration Layer
- **Codegen & type safety:** Generate bindings from the DAR used by the ledger:
  ```bash
  daml codegen ts .daml/dist/erc20-canton-0.0.1.dar -o middleware/src/generated
  ```
  Build failures on mismatched fields surface schema drift early.
- **API surface:** Prefer the HTTP JSON API for web workloads (REST + WebSocket streams); use the Ledger gRPC API for high-frequency or low-latency paths. Subscribe to creation of invitation/proposal contracts to trigger off-ledger actions.
- **Authn/Authz:** Use JWTs signed with the participant’s secret:
  - `actAs`: party on whose behalf commands are submitted (e.g., `Issuer`, `Operator`).
  - `readAs`: parties whose contracts the middleware must query.
  - In dev, `--allow-insecure-tokens` is acceptable; production requires managed keys and scoped tokens per operation.
- **State reads:** Route read-heavy queries (balance/allowance) through the indexer to avoid ledger round-trips; reserve ledger reads for authoritative checks when necessary.

## 5. Validation & Testing Regimes
- **Daml Script > Scenarios:** Scripts run over the real Ledger API (Canton Sandbox or a domain), validating privacy and consensus behavior that in-memory scenarios miss.
- **Deterministic parties:** Use `allocatePartyWithHint` for human-readable IDs in logs and assertions.
- **Example bridge script (pseudo):**
  ```haskell
  testBridge : Script ()
  testBridge = script do
    operator <- allocatePartyWithHint "Operator" (PartyIdHint "Operator")
    alice    <- allocatePartyWithHint "Alice" (PartyIdHint "Alice")
    invite <- submit operator do createCmd UserInvitation with operator; username = alice
    userCid <- submit alice do exerciseCmd invite AcceptInvitation with initialProfile = "v0"
    Some user <- queryContractId alice userCid
    assertEq alice user.username
  ```
- **End-to-end checks:** CI should spin up Canton Sandbox, build the DAR, run bridge scripts, and (optionally) start JSON API to validate token-based flows.

## 6. Canton Infrastructure Considerations
- **Components:** Domain (Sequencer + Mediator) orders and confirms; Participant hosts parties and exposes Ledger/JSON APIs that middleware/indexer use.
- **Key config (`canton.conf` excerpt):**
  ```hocon
  canton.participants.participant1 {
    storage.type = memory        # use postgres for durability
    admin-api.port = 5011
    ledger-api.port = 6865
    ledger-api.address = "0.0.0.0"  # required for Docker/remote clients
  }
  ```
  Misconfigured `ledger-api.address` is a common source of connection errors.
- **Dev orchestration:** `daml start` compiles the package, launches Sandbox, uploads the DAR, runs `init-script` (see `daml/daml.yaml`), and starts the JSON API to provide a ready-to-use bridge target.

## 7. Lifecycle Management
- **Smart Contract Upgrades (SCU):** Support parallel package versions using module prefixes to import V1 and V2 side by side and implement upgrade flows without downtime.
  ```yaml
  module-prefixes:
    erc20-1.0.0: V1
    erc20-2.0.0: V2
  ```
- **Dependency locking:** Always commit `daml.lock`; regenerate only when intentionally updating SDK/library versions to avoid accidental package ID drift.

## 8. Implementation Checklist
- **Repository:** [ ] Add `multi-package.yaml` when splitting packages; [ ] keep `daml.lock` under version control; [ ] co-locate generated bindings with middleware.
- **Ledger design:** [ ] Use Propose/Accept for any multi-party onboarding; [ ] avoid hotspot contracts; [ ] factor shared records.
- **Middleware:** [ ] Regenerate bindings on every contract change; [ ] enforce JWT scopes per operation; [ ] prefer indexer for reads.
- **Validation:** [ ] Replace scenarios with scripts; [ ] run scripts against Sandbox/Canton domain in CI; [ ] use party hints for debuggability.
- **Infra:** [ ] Verify `ledger-api.address`/ports; [ ] automate `daml start` for dev; [ ] secure keys for production tokens.
