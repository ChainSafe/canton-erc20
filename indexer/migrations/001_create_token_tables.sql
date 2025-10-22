-- Migration: create core tables for ERC-20 state projections
--
-- This schema is used by the indexer service to persist holdings,
-- allowances, and token metadata aggregated from the Canton ledger.
-- Apply in order with your favourite migration tool (Flyway, Liquibase, sqlx, etc.).

BEGIN;

CREATE TABLE IF NOT EXISTS tokens (
    token_id      SERIAL PRIMARY KEY,
    symbol        TEXT UNIQUE NOT NULL,
    name          TEXT NOT NULL,
    decimals      INTEGER NOT NULL,
    issuer_party  TEXT NOT NULL,
    created_at    TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE IF NOT EXISTS holdings (
    contract_id   TEXT PRIMARY KEY,
    token_id      INTEGER NOT NULL REFERENCES tokens(token_id) ON DELETE CASCADE,
    owner_party   TEXT NOT NULL,
    amount        NUMERIC NOT NULL,
    last_update   TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE IF NOT EXISTS allowances (
    contract_id   TEXT PRIMARY KEY,
    token_id      INTEGER NOT NULL REFERENCES tokens(token_id) ON DELETE CASCADE,
    owner_party   TEXT NOT NULL,
    spender_party TEXT NOT NULL,
    amount        NUMERIC NOT NULL,
    last_update   TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE INDEX IF NOT EXISTS holdings_token_owner_idx
    ON holdings (token_id, owner_party);

CREATE INDEX IF NOT EXISTS allowances_token_owner_spender_idx
    ON allowances (token_id, owner_party, spender_party);

-- Derived views -------------------------------------------------------------
CREATE OR REPLACE VIEW balances AS
SELECT
    token_id,
    owner_party,
    SUM(amount) AS balance
FROM holdings
GROUP BY token_id, owner_party;

CREATE OR REPLACE VIEW total_supply AS
SELECT
    token_id,
    SUM(amount) AS supply
FROM holdings
GROUP BY token_id;

COMMIT;
