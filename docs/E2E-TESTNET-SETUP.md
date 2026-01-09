# End-to-End Testnet Setup Guide

This guide explains how to set up the Canton EVM Bridge for end-to-end testing using:
- **Ethereum Sepolia** testnet (EVM side)
- **Canton Network quickstart** (Canton side)
- **Canton Middleware** (bridge relayer)

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  ETHEREUM SEPOLIA (Chain ID: 11155111)                      │
│  ├─ CantonBridge: 0x523a865Bf51d93df22Fb643e6BDE2F66438e32c2│
│  └─ TokenRegistry: 0x675E7eE05D1d7376DC0a6d233440bF9753Ba6f9F│
└─────────────────────────┬───────────────────────────────────┘
                          │ JSON-RPC (Alchemy)
┌─────────────────────────▼───────────────────────────────────┐
│  CANTON MIDDLEWARE (Go relayer)                             │
│  ├─ Watches DepositToCanton events on Ethereum              │
│  ├─ Mints CIP-56 tokens on Canton                           │
│  ├─ Watches WithdrawalRequest on Canton                     │
│  └─ Releases ERC-20 on Ethereum                             │
└─────────────────────────┬───────────────────────────────────┘
                          │ gRPC + OAuth2
┌─────────────────────────▼───────────────────────────────────┐
│  CANTON NETWORK (cn-quickstart)                             │
│  ├─ Ledger API: localhost:3901 (app-provider)               │
│  ├─ Keycloak: localhost:8082                                │
│  ├─ PostgreSQL: localhost:15432                             │
│  └─ DAR Packages:                                           │
│      ├─ bridge-wayfinder-v2-1.1.0.dar                       │
│      ├─ bridge-core-v2-1.1.0.dar                            │
│      └─ cip56-token-v2-1.1.0.dar                            │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **Docker & Docker Compose** - For cn-quickstart
2. **Go 1.21+** - For canton-middleware
3. **Foundry** - For Ethereum interactions
4. **Nix & direnv** - For cn-quickstart environment
5. **Daml SDK 3.4.8** - For building DAR files

## Step 1: Ethereum Sepolia (Already Deployed)

The Solidity contracts are already deployed on Sepolia:

| Contract | Address |
|----------|---------|
| CantonBridge | `0x523a865Bf51d93df22Fb643e6BDE2F66438e32c2` |
| TokenRegistry | `0x675E7eE05D1d7376DC0a6d233440bF9753Ba6f9F` |

**Relayer Account:**
- Address: `0x88ce832A05eE26C9a4011e2d9cf957f97F43B08C`
- Has ADMIN_ROLE and RELAYER_ROLE on CantonBridge

**RPC Endpoint:**
```
https://eth-sepolia.g.alchemy.com/v2/MeMdx3uk0ZFuSy2YFs0VAGjG7gXf0wJP
```

## Step 2: Canton Network Quickstart

### 2.1 Start Canton Services

```bash
cd ~/chainsafe/cn-quickstart/quickstart

# Setup (if not done)
make setup
# - Observability: Yes
# - OAuth2: Yes
# - Party Hint: quickstart-skynet-1
# - Test Mode: No

# Build
make build

# Start services
make start

# Wait for healthy status
docker ps  # All containers should show (healthy)
```

### 2.2 Copy DAR Files

```bash
cd ~/chainsafe/canton-erc20

# Build DAR files
./scripts/build-all.sh

# Copy to cn-quickstart
./scripts/deploy-canton.sh copy

# Verify
ls ~/chainsafe/cn-quickstart/quickstart/daml/canton-erc20/
```

### 2.3 Upload DAR Files to Canton

Open Canton console:
```bash
cd ~/chainsafe/cn-quickstart/quickstart
make canton-console
```

In the console:
```scala
// Upload bridge packages
val darPath = "/home/skynet/chainsafe/cn-quickstart/quickstart/daml/canton-erc20"

participant_app_provider.dars.upload(s"$darPath/common-v2-1.1.0.dar")
participant_app_provider.dars.upload(s"$darPath/cip56-token-v2-1.1.0.dar")
participant_app_provider.dars.upload(s"$darPath/bridge-core-v2-1.1.0.dar")
participant_app_provider.dars.upload(s"$darPath/bridge-wayfinder-v2-1.1.0.dar")

// List packages to get IDs
participant_app_provider.packages.list().filter(_.name.contains("bridge"))

// Allocate relayer party
val relayerParty = participant_app_provider.parties.allocate("BridgeRelayer", participant_app_provider.id)
println(s"Relayer Party: ${relayerParty.toLf}")

// Get domain ID
val domainId = synchronizers.all.head._2.synchronizerId
println(s"Domain ID: $domainId")
```

Record these values:
- `CANTON_RELAYER_PARTY`: e.g., `BridgeRelayer::1220abcd...`
- `CANTON_BRIDGE_PACKAGE_ID`: Package ID of bridge-wayfinder-v2
- `CANTON_DOMAIN_ID`: e.g., `global-domain::12209d6e...`

## Step 3: Configure Middleware

### 3.1 Set Up Database

```bash
# Connect to cn-quickstart PostgreSQL
PGPASSWORD='supersafe' psql -h localhost -p 15432 -U cnadmin -d postgres

-- Create bridge database and user
CREATE ROLE bridge WITH LOGIN PASSWORD 'bridge_secret';
CREATE DATABASE canton_bridge OWNER bridge;
GRANT ALL PRIVILEGES ON DATABASE canton_bridge TO bridge;
\q
```

### 3.2 Create Configuration

Create `~/chainsafe/canton-middleware/.env.local`:
```bash
# Ethereum Sepolia
ETHEREUM_RELAYER_PRIVATE_KEY=0x082560991dcfb10aff28a973120329d0fbf1e490357cfcf15ad9d17548c29eb2

# Canton (update with values from Step 2.3)
CANTON_DOMAIN_ID=global-domain::12209d6e7b53...
CANTON_RELAYER_PARTY=BridgeRelayer::1220...
CANTON_BRIDGE_PACKAGE_ID=<package_id_from_step_2.3>
```

The middleware config file is at:
`~/chainsafe/canton-middleware/config.sepolia-quickstart.yaml`

### 3.3 Build and Run Middleware

```bash
cd ~/chainsafe/canton-middleware

# Load environment
source .env.local

# Build
go build -o bin/relayer ./cmd/relayer

# Run
./bin/relayer -config config.sepolia-quickstart.yaml
```

## Step 4: End-to-End Test

### 4.1 Register a Test Token

First, deploy or use an existing ERC-20 on Sepolia, then register it:

```bash
cd ~/chainsafe/canton-erc20/ethereum

# Register token in TokenRegistry
forge script script/RegisterToken.s.sol:RegisterToken \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast \
  -vvv
```

### 4.2 Perform a Deposit (Ethereum → Canton)

```bash
# Approve bridge to spend tokens
cast send $TOKEN_ADDRESS "approve(address,uint256)" \
  $BRIDGE_ADDRESS 1000000000000000000 \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --private-key "$PRIVATE_KEY"

# Deposit to Canton (recipient is Canton fingerprint)
cast send $BRIDGE_ADDRESS "depositToCanton(address,uint256,bytes32)" \
  $TOKEN_ADDRESS 1000000000000000000 0x<canton_fingerprint> \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --private-key "$PRIVATE_KEY"
```

Watch middleware logs for:
1. `Detected DepositToCanton event`
2. `Processing deposit...`
3. `Minted CIP-56 holding on Canton`

### 4.3 Verify on Canton

In Canton console:
```scala
// Check holdings
participant_app_provider.ledger_api.state.active_contracts()
  .filter(_.templateId.toString.contains("CIP56Holding"))
```

### 4.4 Perform a Withdrawal (Canton → Ethereum)

In Canton console:
```scala
// Find user's holding
val holdings = participant_app_provider.ledger_api.state.active_contracts()
  .filter(_.templateId.toString.contains("CIP56Holding"))

// Exercise withdrawal
// (Implementation depends on bridge contract design)
```

Watch middleware logs for:
1. `Detected WithdrawalRequest`
2. `Processing withdrawal...`
3. `Released ERC-20 on Ethereum`

## Port Reference

| Service | Port | Description |
|---------|------|-------------|
| Canton Ledger API (app-user) | 2901 | gRPC |
| Canton Ledger API (app-provider) | 3901 | gRPC |
| Canton Ledger API (sv) | 4901 | gRPC |
| Canton Admin API (app-provider) | 3902 | gRPC |
| Keycloak | 8082 | OAuth2 |
| PostgreSQL | 15432 | Database |
| App User UI | 2000 | Web UI |
| App Provider UI | 3000 | Web UI |
| SV UI | 4000 | Web UI |
| Middleware | 8080 | REST API |
| Middleware Metrics | 9091 | Prometheus |

## Troubleshooting

### Canton Services Not Starting
```bash
# Check container logs
docker logs canton
docker logs splice

# Check health
docker ps --format "table {{.Names}}\t{{.Status}}"
```

### OAuth2 Authentication Issues
- Ensure Keycloak is running on port 8082
- Check token endpoint: `http://localhost:8082/realms/splice/protocol/openid-connect/token`
- Verify audience matches configuration

### Database Connection Issues
```bash
# Test PostgreSQL connection
PGPASSWORD='supersafe' psql -h localhost -p 15432 -U cnadmin -d postgres -c "SELECT 1"
```

### Ethereum Transaction Failures
```bash
# Check balance
cast balance $RELAYER_ADDRESS --rpc-url "$SEPOLIA_RPC_URL"

# Check gas price
cast gas-price --rpc-url "$SEPOLIA_RPC_URL"
```

## Files Reference

| Project | Key Files |
|---------|-----------|
| canton-erc20 | `ethereum/.env`, `ethereum/broadcast/Deploy.s.sol/11155111/run-latest.json` |
| canton-middleware | `config.sepolia-quickstart.yaml`, `.env.local` |
| cn-quickstart | `.env.local`, `daml/canton-erc20/*.dar` |
