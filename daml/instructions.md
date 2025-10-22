# Canton ERC-20 Dev Workflow

These steps mirror the behaviour of `scripts/bootstrap.sh` and assume you are running from the repository root (`/Users/s3b/Dev/canton`).

## 1. Bootstrap the sandbox and JSON API

```
./canton-ERC20/scripts/bootstrap.sh
```

What the script does:
- Builds the DAR.
- Starts (or reuses) the sandbox on `${SANDBOX_PORT:-6865}`.
- Uploads the DAR and runs the bootstrap DAML scripts.
- Ensures the Issuer/Alice/Bob parties exist.
- Starts (or reuses) the JSON API on `${JSON_API_PORT:-7575}` with `json-api.conf`.
- Generates helper exports and writes them to `canton-ERC20/dev-env.sh`.

Logs & PIDs are written to `canton-ERC20/log/`.

## 2. Load the helper environment exports

Run this in every shell where you’ll call curl:

```
source canton-ERC20/dev-env.sh
```

The file defines:

```
LEDGER_ID            # defaults to sandbox
SANDBOX_PORT         # defaults to 6865
JSON_API_PORT        # defaults to 7575
DEV_SECRET           # defaults to dev-secret
ERC20_PKG_ID         # package id for erc20-canton DAR
ISSUER_PARTY         # fully qualified issuer party id
ALICE_PARTY          # fully qualified Alice party id
BOB_PARTY            # fully qualified Bob party id
TOKEN_ISSUER         # JWT acting as issuer (also exported as TOKEN for convenience)
TOKEN_ALICE          # JWT acting as alice
TOKEN_BOB            # JWT acting as bob
TOKEN_ISSUER_ALICE   # JWT acting as issuer & alice
TOKEN                # alias for TOKEN_ISSUER
```

## 3. JSON API queries & commands

With the exports loaded, the curl examples below can be run as-is.

### 3.1 List active contracts

```
curl -s http://localhost:${JSON_API_PORT}/v1/query \
  -H "Authorization: Bearer $TOKEN_ISSUER" \
  -H "Content-type: application/json" \
  -d "{\"templateIds\":[\"$ERC20_PKG_ID:ERC20.Token:TokenManager\"],\"query\":{}}" | jq

curl -s http://localhost:${JSON_API_PORT}/v1/query \
  -H "Authorization: Bearer $TOKEN_ISSUER" \
  -H "Content-type: application/json" \
  -d "{\"templateIds\":[\"$ERC20_PKG_ID:ERC20.Token:TokenHolding\"],\"query\":{}}" | jq
```

### 3.2 Create a `TokenManager`

```
TM_JSON=$(
  curl -s http://localhost:${JSON_API_PORT}/v1/create \
    -H "Authorization: Bearer $TOKEN_ISSUER" \
    -H "Content-type: application/json" \
    -d '{
          "templateId":"'"$ERC20_PKG_ID"':ERC20.Token:TokenManager",
          "payload":{
            "issuer":"'"$ISSUER_PARTY"'",
            "meta":{"name":"Canton Coin","symbol":"CCN","decimals":6}
          }
        }'
)
echo "${TM_JSON}" | jq
export TM_CID=$(echo "${TM_JSON}" | jq -r '.result.contractId')
```

### 3.3 Mint to Alice

```
curl -s http://localhost:${JSON_API_PORT}/v1/exercise \
  -H "Authorization: Bearer $TOKEN_ISSUER" \
  -H "Content-type: application/json" \
  -d "{
        \"templateId\":\"$ERC20_PKG_ID:ERC20.Token:TokenManager\",
        \"contractId\":\"$TM_CID\",
        \"choice\":\"Mint\",
        \"argument\":{\"to\":\"$ALICE_PARTY\",\"amount\":100.0}
      }" | jq
```

### 3.4 Find Alice holdings

```
export HOLD_CID=$(
  curl -s http://localhost:${JSON_API_PORT}/v1/query \
    -H "Authorization: Bearer $TOKEN_ISSUER" \
    -H "Content-type: application/json" \
    -d "{\"templateIds\":[\"$ERC20_PKG_ID:ERC20.Token:TokenHolding\"],\"query\":{}}" |
    jq --arg alice "$ALICE_PARTY" -r '.result[] | select(.payload.owner==$alice) | .contractId' |
    head -n 1
)
echo "Alice holding CID: $HOLD_CID"
```

### 3.5 Transfer 30.0 from Alice to Bob

```
curl -s "http://localhost:${JSON_API_PORT}/v1/exercise?actAs=$ALICE_PARTY" \
  -H "Authorization: Bearer $TOKEN_ALICE" \
  -H "Content-type: application/json" \
  -d "{
        \"templateId\":\"$ERC20_PKG_ID:ERC20.Token:TokenHolding\",
        \"contractId\":\"$HOLD_CID\",
        \"choice\":\"Transfer\",
        \"argument\":{\"to\":\"$BOB_PARTY\",\"value\":30.0}
      }" | jq
```

Alternative with the actAs meta block (use instead of the call above, or rerun the query in §3.4 to refresh `HOLD_CID` first, because the transfer archives the contract):

```
export HOLD_CID=$(
  curl -s http://localhost:${JSON_API_PORT}/v1/query \
    -H "Authorization: Bearer $TOKEN_ISSUER" \
    -H "Content-type: application/json" \
    -d "{\"templateIds\":[\"$ERC20_PKG_ID:ERC20.Token:TokenHolding\"],\"query\":{}}" |
    jq --arg alice "$ALICE_PARTY" -r '.result[] | select(.payload.owner==$alice) | .contractId' |
    head -n 1
)

curl -s http://localhost:${JSON_API_PORT}/v1/exercise \
  -H "Authorization: Bearer $TOKEN_ALICE" \
  -H "Content-type: application/json" \
  -d "{
        \"templateId\":\"$ERC20_PKG_ID:ERC20.Token:TokenHolding\",
        \"contractId\":\"$HOLD_CID\",
        \"choice\":\"Transfer\",
        \"argument\":{\"to\":\"$BOB_PARTY\",\"value\":30.0},
        \"meta\":{\"actAs\":[\"$ALICE_PARTY\"]}
      }" | jq
```

### 3.6 Stream holdings (Server-Sent Events)

Will add this later , streaming isn’t available without a query store. 


## 4. Notes

- To customise ports/secrets, set `SANDBOX_PORT`, `JSON_API_PORT`, `DEV_SECRET`, or `LEDGER_ID` before running `bootstrap.sh`.
- Re-run `bootstrap.sh` whenever you need a clean slate; it’s idempotent and will reuse running services.
- Always re-`source canton-ERC20/dev-env.sh` in new terminals before using the curl commands.
