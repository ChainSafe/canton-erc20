// Simple ERC-20 middleware vertical slice.
// Implements only BalanceOf using the indexer HTTP endpoint.

const path = require('path');
const grpc = require('@grpc/grpc-js');
const protoLoader = require('@grpc/proto-loader');
const axios = require('axios');

const PROTO_PATH = path.join(__dirname, 'proto', 'erc20.proto');
const INDEXER_BASE_URL = process.env.INDEXER_BASE_URL ?? 'http://localhost:9000';
const DEFAULT_SYMBOL = process.env.DEFAULT_SYMBOL ?? 'CCN';
const PORT = process.env.PORT ? Number(process.env.PORT) : 50051;
const INDEXER_API_TOKEN = process.env.INDEXER_API_TOKEN;

const packageDefinition = protoLoader.loadSync(PROTO_PATH, {
  keepCase: true,
  longs: String,
  enums: String,
  defaults: true,
  oneofs: true,
});

const erc20Proto = grpc.loadPackageDefinition(packageDefinition).canton.erc20.v1;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function indexerHeaders() {
  if (!INDEXER_API_TOKEN) return undefined;
  return { Authorization: INDEXER_API_TOKEN.startsWith('Bearer ') ? INDEXER_API_TOKEN : `Bearer ${INDEXER_API_TOKEN}` };
}

async function requestIndexer(path, params) {
  const url = `${INDEXER_BASE_URL}${path}`;
  const response = await axios.get(url, {
    timeout: 2500,
    params,
    headers: indexerHeaders(),
  });
  return response.data;
}

async function fetchBalance(symbol, party) {
  const data = await requestIndexer('/balanceOf', { symbol, party });
  return data.balance ?? '0';
}

async function fetchTotalSupply(symbol) {
  const data = await requestIndexer('/totalSupply', { symbol });
  return data.total ?? '0';
}

async function fetchAllowance(symbol, owner, spender) {
  const data = await requestIndexer('/allowance', { symbol, owner, spender });
  return data.allowance ?? '0';
}

function unwrapParty(fieldName, addr) {
  if (!addr || !addr.party) {
    throw new Error(`${fieldName}.party is required`);
  }
  return addr.party;
}

function unwrapToken(token) {
  return token?.symbol ?? DEFAULT_SYMBOL;
}

// ---------------------------------------------------------------------------
// gRPC handlers
// ---------------------------------------------------------------------------
async function balanceOf(call, callback) {
  try {
    const symbol = unwrapToken(call.request.token);
    const party = unwrapParty('owner', call.request.owner);
    const balance = await fetchBalance(symbol, party);
    callback(null, {
      token: { symbol },
      owner: { party },
      balance: { value: balance },
    });
  } catch (err) {
    console.error('[middleware] BalanceOf error', err.message);
    callback({
      code: grpc.status.INTERNAL,
      message: err.message ?? 'BalanceOf failed',
    });
  }
}

async function totalSupply(call, callback) {
  try {
    const symbol = unwrapToken(call.request.token);
    const total = await fetchTotalSupply(symbol);
    callback(null, {
      token: { symbol },
      total: { value: total },
    });
  } catch (err) {
    console.error('[middleware] TotalSupply error', err.message);
    callback({
      code: grpc.status.INTERNAL,
      message: err.message ?? 'TotalSupply failed',
    });
  }
}

async function allowance(call, callback) {
  try {
    const symbol = unwrapToken(call.request.token);
    const owner = unwrapParty('owner', call.request.owner);
    const spender = unwrapParty('spender', call.request.spender);
    const allowanceValue = await fetchAllowance(symbol, owner, spender);
    callback(null, {
      token: { symbol },
      owner: { party: owner },
      spender: { party: spender },
      allowance: { value: allowanceValue },
    });
  } catch (err) {
    console.error('[middleware] Allowance error', err.message);
    callback({
      code: grpc.status.INTERNAL,
      message: err.message ?? 'Allowance failed',
    });
  }
}

function unimplemented(method) {
  return (call, callback) => {
    const msg = `${method} not implemented in vertical slice`;
    console.warn('[middleware]', msg);
    callback({ code: grpc.status.UNIMPLEMENTED, message: msg });
  };
}

function main() {
  const server = new grpc.Server();
  server.addService(erc20Proto.ERC20Service.service, {
    BalanceOf: balanceOf,
    TotalSupply: totalSupply,
    Allowance: allowance,
    Transfer: unimplemented('Transfer'),
    Approve: unimplemented('Approve'),
    TransferFrom: unimplemented('TransferFrom'),
    Mint: unimplemented('Mint'),
    Burn: unimplemented('Burn'),
  });

  server.bindAsync(`0.0.0.0:${PORT}`, grpc.ServerCredentials.createInsecure(), (err) => {
    if (err) {
      console.error('[middleware] Failed to bind', err);
      process.exit(1);
    }
    server.start();
    console.log(`[middleware] gRPC server listening on ${PORT}`);
    console.log(`[middleware] Using indexer at ${INDEXER_BASE_URL}`);
    if (INDEXER_API_TOKEN) {
      console.log('[middleware] Indexer authorization enabled');
    }
  });
}

main();
