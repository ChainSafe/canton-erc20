// canton-indexer/index.js
import axios from 'axios';
import express from 'express';
import Decimal from 'decimal.js-light';

import { EventSource as EventSourcePolyfill } from 'eventsource';

const EventSource = EventSourcePolyfill ?? (() => {
  throw new Error('EventSource export not found');
});

// -----------------------------------------------------------------------------
// Configuration
// -----------------------------------------------------------------------------
const JSON_API = process.env.JSON_API ?? 'http://127.0.0.1:7575';
const TOKEN_SYMBOL = process.env.TOKEN_SYMBOL ?? 'CCN';        // default token
const PORT = parseInt(process.env.PORT ?? '9000', 10);
const ERC20_PKG_ID = process.env.ERC20_PKG_ID;
const JSON_API_TOKEN = process.env.JSON_API_TOKEN ?? process.env.TOKEN_ISSUER ?? process.env.TOKEN;
const DISABLE_STREAM = process.env.DISABLE_STREAM === '1';
const POLL_INTERVAL_MS = parseInt(process.env.POLL_INTERVAL_MS ?? '5000', 10);
if (!ERC20_PKG_ID) {
  console.error('[indexer] ERC20_PKG_ID environment variable is required (e.g. af64e5...)');
  process.exit(1);
}

// If your JSON API enforces auth, set JSON_API_TOKEN to "Bearer <jwt>"; otherwise leave undefined.
const AUTH_HEADER = JSON_API_TOKEN ? (JSON_API_TOKEN.startsWith('Bearer ') ? JSON_API_TOKEN : `Bearer ${JSON_API_TOKEN}`) : undefined;

const TEMPLATE_IDS = {
  holding: `${ERC20_PKG_ID}:ERC20.Token:TokenHolding`,
  allowance: `${ERC20_PKG_ID}:ERC20.Allowance:Allowance`,
};

// -----------------------------------------------------------------------------
// In-memory state
// -----------------------------------------------------------------------------
const holdingsByCid = new Map();   // contractId -> {owner, amount, symbol}
const allowanceByCid = new Map();  // contractId -> {owner, spender, amount, symbol}

// Derived views
let balances = new Map();          // key: `${symbol}:${party}` -> Decimal
let allowances = new Map();        // key: `${symbol}:${owner}:${spender}` -> Decimal
let totalSupply = new Map();       // key: symbol -> Decimal
let pollTimer = null;

// Utility helpers ------------------------------------------------------------
const KEY_BAL = (symbol, party) => `${symbol}:${party}`;
const KEY_ALLOW = (symbol, owner, spender) => `${symbol}:${owner}:${spender}`;

function sumBalances() {
  const bal = new Map();
  const supply = new Map();
  for (const { owner, amount, symbol } of holdingsByCid.values()) {
    const key = KEY_BAL(symbol, owner);
    bal.set(key, (bal.get(key) ?? new Decimal(0)).add(amount));
    supply.set(symbol, (supply.get(symbol) ?? new Decimal(0)).add(amount));
  }
  balances = bal;
  totalSupply = supply;
}

function sumAllowances() {
  const all = new Map();
  for (const { owner, spender, amount, symbol } of allowanceByCid.values()) {
    const key = KEY_ALLOW(symbol, owner, spender);
    all.set(key, amount);
  }
  allowances = all;
}

function decimalFrom(value) {
  try {
    return new Decimal(value);
  } catch {
    return new Decimal(0);
  }
}

function parseHolding(payload) {
  const { owner, amount, meta } = payload;
  return {
    owner,
    amount: decimalFrom(amount),
    symbol: meta?.symbol ?? TOKEN_SYMBOL,
  };
}

function parseAllowance(payload) {
  const { owner, spender, limit, meta } = payload;
  return {
    owner,
    spender,
    amount: decimalFrom(limit),
    symbol: meta?.symbol ?? TOKEN_SYMBOL,
  };
}

// -----------------------------------------------------------------------------
// Bootstrapping: load active contracts once
// -----------------------------------------------------------------------------
async function refreshState({ log = true } = {}) {
  if (log) console.log('[indexer] Refreshing contracts from JSON API…');

  const headers = { 'Content-Type': 'application/json' };
  if (AUTH_HEADER) headers.Authorization = AUTH_HEADER;

  // Token holdings
  const holdRes = await axios.post(
    `${JSON_API}/v1/query`,
    { templateIds: [TEMPLATE_IDS.holding], query: {} },
    { headers },
  );
  holdingsByCid.clear();
  for (const res of holdRes.data.result ?? []) {
    const cid = res.contractId;
    const holding = parseHolding(res.payload);
    holdingsByCid.set(cid, holding);
  }

  // Allowances
  const allowRes = await axios.post(
    `${JSON_API}/v1/query`,
    { templateIds: [TEMPLATE_IDS.allowance], query: {} },
    { headers },
  );
  allowanceByCid.clear();
  for (const res of allowRes.data.result ?? []) {
    const cid = res.contractId;
    const allowance = parseAllowance(res.payload);
    allowanceByCid.set(cid, allowance);
  }

  sumBalances();
  sumAllowances();

  if (log) {
    console.log('[indexer] Snapshot loaded.',
      `Holdings: ${holdingsByCid.size}, Allowances: ${allowanceByCid.size}`);
  }
}

// -----------------------------------------------------------------------------
// Live updates: subscribe to JSON API event stream
// -----------------------------------------------------------------------------
function startStream() {
  if (DISABLE_STREAM) {
    console.log('[indexer] Streaming disabled via DISABLE_STREAM=1; using polling mode.');
    startPolling();
    return;
  }

  const headers = {};
  if (AUTH_HEADER) headers.Authorization = AUTH_HEADER;

  const payload = JSON.stringify({
    templateIds: [
      { templateId: TEMPLATE_IDS.holding },
      { templateId: TEMPLATE_IDS.allowance },
    ],
    query: [{}],      // no predicate; receive all
  });

  const es = new EventSource(`${JSON_API}/v1/stream/query`, {
    headers,
    // eventsource polyfill lets us POST via method + payload
    method: 'POST',
    payload,
  });

  es.onmessage = evt => {
    stopPolling();

    const msg = JSON.parse(evt.data);
    if (!msg.events) return;

    for (const ev of msg.events) {
      if (ev.created) {
        handleCreated(ev.created);
      } else if (ev.archived) {
        handleArchived(ev.archived);
      }
    }

    sumBalances();
    sumAllowances();
  };

  es.onerror = err => {
    const message = err?.message ?? '';
    // JSON API returns 400 if the query-stream endpoint is not enabled (requires query store)
    if (err?.code === 400 || message.includes('Non-200 status code (400')) {
      console.warn('[indexer] JSON API stream endpoint returned 400. Falling back to polling (enable query store to use streaming).');
      es.close();
      startPolling();
      return;
    }
    if (err?.code === 401) {
      console.error('[indexer] Stream authorization failed (401). Check JSON_API_TOKEN.');
      es.close();
      setTimeout(startStream, 5000);
      return;
    }
    console.error('[indexer] Stream error, retrying in 2s…', err);
    es.close();
    setTimeout(startStream, 2000);
  };

  console.log('[indexer] Streaming JSON API events…');
}

function startPolling() {
  if (pollTimer) return;
  console.log(`[indexer] Polling JSON API every ${POLL_INTERVAL_MS}ms…`);
  pollTimer = setInterval(async () => {
    try {
      await refreshState({ log: false });
    } catch (err) {
      console.error('[indexer] Polling error:', err?.message ?? err);
    }
  }, POLL_INTERVAL_MS);
}

function stopPolling() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}

function handleCreated(created) {
  const { templateId, contractId, payload } = created;
  const tid = templateId?.templateId ?? templateId;
  switch (tid) {
    case TEMPLATE_IDS.holding:
    case 'ERC20.Token:TokenHolding':
      holdingsByCid.set(contractId, parseHolding(payload));
      break;
    case TEMPLATE_IDS.allowance:
    case 'ERC20.Allowance:Allowance':
      allowanceByCid.set(contractId, parseAllowance(payload));
      break;
    default:
      break;
  }
}

function handleArchived(archived) {
  const { templateId, contractId } = archived;
  const tid = templateId?.templateId ?? templateId;
  switch (tid) {
    case TEMPLATE_IDS.holding:
    case 'ERC20.Token:TokenHolding':
      holdingsByCid.delete(contractId);
      break;
    case TEMPLATE_IDS.allowance:
    case 'ERC20.Allowance:Allowance':
      allowanceByCid.delete(contractId);
      break;
    default:
      break;
  }
}

// -----------------------------------------------------------------------------
// Simple HTTP interface for the middleware to consume
// -----------------------------------------------------------------------------
const app = express();

app.get('/healthz', (_req, res) => {
  res.json({
    status: 'ok',
    holdings: holdingsByCid.size,
    allowances: allowanceByCid.size,
    updatedAt: new Date().toISOString(),
  });
});

app.get('/balanceOf', (req, res) => {
  const { symbol = TOKEN_SYMBOL, party } = req.query;
  if (!party) return res.status(400).json({ error: 'party is required' });

  const key = KEY_BAL(symbol, party);
  const amount = balances.get(key) ?? new Decimal(0);
  res.json({ symbol, party, balance: amount.toString() });
});

app.get('/totalSupply', (req, res) => {
  const { symbol = TOKEN_SYMBOL } = req.query;
  const total = totalSupply.get(symbol) ?? new Decimal(0);
  res.json({ symbol, total: total.toString() });
});

app.get('/allowance', (req, res) => {
  const { symbol = TOKEN_SYMBOL, owner, spender } = req.query;
  if (!owner || !spender) {
    return res.status(400).json({ error: 'owner and spender are required' });
  }

  const key = KEY_ALLOW(symbol, owner, spender);
  const amount = allowances.get(key) ?? new Decimal(0);
  res.json({ symbol, owner, spender, allowance: amount.toString() });
});

app.get('/state', (req, res) => {
  // handy debug endpoint
  res.json({
    holdingsSize: holdingsByCid.size,
    allowancesSize: allowanceByCid.size,
    balances: Object.fromEntries([...balances].map(([k, v]) => [k, v.toString()])),
    totalSupply: Object.fromEntries([...totalSupply].map(([k, v]) => [k, v.toString()])),
  });
});

// -----------------------------------------------------------------------------
// Entry point
// -----------------------------------------------------------------------------
async function main() {
  try {
    console.log('[indexer] Config', {
      JSON_API,
      PORT,
      TOKEN_SYMBOL,
      ERC20_PKG_ID,
      auth: Boolean(AUTH_HEADER),
      pollIntervalMs: POLL_INTERVAL_MS,
      streamingDisabled: DISABLE_STREAM,
    });
    await refreshState({ log: true });
    startStream();

    app.listen(PORT, () => {
      console.log(`[indexer] HTTP server listening on port ${PORT}`);
      console.log(`[indexer] Try: curl "http://localhost:${PORT}/balanceOf?party=<partyId>"`);
    });
  } catch (err) {
    console.error('[indexer] Failed to start:', err);
    process.exit(1);
  }
}

main();
process.on('SIGINT', () => {
  stopPolling();
  console.log('\n[indexer] Shutting down.');
  process.exit(0);
});
