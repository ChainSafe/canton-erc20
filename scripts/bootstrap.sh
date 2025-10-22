#!/usr/bin/env bash

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
SANDBOX_PORT="${SANDBOX_PORT:-6865}"
JSON_API_PORT="${JSON_API_PORT:-7575}"
DEV_SECRET="${DEV_SECRET:-dev-secret}"
LEDGER_ID="${LEDGER_ID:-sandbox}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DAML_DIR="${REPO_ROOT}/daml"
JSON_API_CONFIG="${REPO_ROOT}/json-api.conf"
LOG_DIR="${REPO_ROOT}/log"
mkdir -p "${LOG_DIR}"

SANDBOX_LOG="${LOG_DIR}/sandbox-bootstrap.log"
JSON_API_LOG="${LOG_DIR}/json-api-bootstrap.log"
SANDBOX_PID_FILE="${LOG_DIR}/sandbox-bootstrap.pid"
JSON_API_PID_FILE="${LOG_DIR}/json-api-bootstrap.pid"
ENV_FILE="${REPO_ROOT}/dev-env.sh"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
log() {
  printf '[bootstrap] %s\n' "$*" >&2
}

wait_for_ledger() {
  local retries=30
  for ((i=1; i<=retries; i++)); do
    if daml ledger list-parties --host localhost --port "${SANDBOX_PORT}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_json_api() {
  local retries=30
  for ((i=1; i<=retries; i++)); do
    if curl -sf "http://localhost:${JSON_API_PORT}/livez" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

b64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

generate_token() {
  local act_as_json="$1"
  local hdr payload pay_b64 sig_b64
  hdr=$(printf '%s' '{"alg":"HS256","typ":"JWT"}' | b64url)
  payload=$(printf '{"https://daml.com/ledger-api":{"ledgerId":"%s","applicationId":"dev-app","actAs":%s}}' "${LEDGER_ID}" "${act_as_json}")
  pay_b64=$(printf '%s' "${payload}" | b64url)
  sig_b64=$(printf '%s' "${hdr}.${pay_b64}" | openssl dgst -sha256 -mac HMAC -macopt key:${DEV_SECRET} -binary | b64url)
  printf '%s.%s.%s' "${hdr}" "${pay_b64}" "${sig_b64}"
}

# -----------------------------------------------------------------------------
# 1. Build DAR
# -----------------------------------------------------------------------------
log "Building DAR in ${DAML_DIR}"
(cd "${DAML_DIR}" && daml clean && daml build)

# -----------------------------------------------------------------------------
# 2. Start sandbox (if not already running)
# -----------------------------------------------------------------------------
if ! daml ledger list-parties --host localhost --port "${SANDBOX_PORT}" >/dev/null 2>&1; then
  log "Starting sandbox on port ${SANDBOX_PORT}"
  (cd "${DAML_DIR}" && nohup daml sandbox --port "${SANDBOX_PORT}" >"${SANDBOX_LOG}" 2>&1 & echo $! > "${SANDBOX_PID_FILE}")
  if ! wait_for_ledger; then
    log "Sandbox did not become ready; see ${SANDBOX_LOG}"
    exit 1
  fi
else
  log "Sandbox already running on port ${SANDBOX_PORT}"
fi

# -----------------------------------------------------------------------------
# 3. Upload DAR and run scripts
# -----------------------------------------------------------------------------
log "Uploading DAR to sandbox"
(cd "${DAML_DIR}" && daml ledger upload-dar --host localhost --port "${SANDBOX_PORT}" ./.daml/dist/erc20-canton-0.0.1.dar)

log "Running bootstrap scripts"
(cd "${DAML_DIR}" && daml script --ledger-host localhost --ledger-port "${SANDBOX_PORT}" --dar ./.daml/dist/erc20-canton-0.0.1.dar --script-name ERC20.Script:test)
(cd "${DAML_DIR}" && daml script --ledger-host localhost --ledger-port "${SANDBOX_PORT}" --dar ./.daml/dist/erc20-canton-0.0.1.dar --script-name ERC20.Inspect:balancesOk)

log "Ensuring Issuer/Alice/Bob parties exist"
daml ledger allocate-parties --host localhost --port "${SANDBOX_PORT}" Issuer Alice Bob >/dev/null

# -----------------------------------------------------------------------------
# 4. Start JSON API (if not already running)
# -----------------------------------------------------------------------------
if ! curl -sf "http://localhost:${JSON_API_PORT}/livez" >/dev/null 2>&1; then
  log "Starting JSON API on port ${JSON_API_PORT}"
  (cd "${DAML_DIR}" && nohup daml json-api --config "${JSON_API_CONFIG}" >"${JSON_API_LOG}" 2>&1 & echo $! > "${JSON_API_PID_FILE}")
  if ! wait_for_json_api; then
    log "JSON API did not become ready; see ${JSON_API_LOG}"
    exit 1
  fi
else
  log "JSON API already running on port ${JSON_API_PORT}"
fi

# -----------------------------------------------------------------------------
# 5. Compute environment exports
# -----------------------------------------------------------------------------
log "Computing helper environment variables"

ERC20_PKG_ID=$(
  daml damlc inspect-dar "${DAML_DIR}/.daml/dist/erc20-canton-0.0.1.dar" |
    grep -m1 'erc20-canton-0.0.1-' |
    sed -E 's|.*erc20-canton-0.0.1-([0-9a-f]+).*|\1|'
)

ISSUER_PARTY=$(
  daml ledger list-parties --host localhost --port "${SANDBOX_PORT}" |
    awk -F"'" '/displayName = "Issuer"/ {print $2; exit}'
)
ALICE_PARTY=$(
  daml ledger list-parties --host localhost --port "${SANDBOX_PORT}" |
    awk -F"'" '/displayName = "Alice"/ {print $2; exit}'
)
BOB_PARTY=$(
  daml ledger list-parties --host localhost --port "${SANDBOX_PORT}" |
    awk -F"'" '/displayName = "Bob"/ {print $2; exit}'
)

if [[ -z "${ISSUER_PARTY}" || -z "${ALICE_PARTY}" || -z "${BOB_PARTY}" ]]; then
  log "Failed to resolve party identifiers; aborting."
  exit 1
fi

TOKEN_ISSUER=$(generate_token "[\"${ISSUER_PARTY}\"]")
TOKEN_ALICE=$(generate_token "[\"${ALICE_PARTY}\"]")
TOKEN_BOB=$(generate_token "[\"${BOB_PARTY}\"]")
TOKEN_ISSUER_ALICE=$(generate_token "[\"${ISSUER_PARTY}\",\"${ALICE_PARTY}\"]")
TOKEN="${TOKEN_ISSUER}"

cat > "${ENV_FILE}" <<EOF
# Generated by scripts/bootstrap.sh
export LEDGER_ID="${LEDGER_ID}"
export SANDBOX_PORT="${SANDBOX_PORT}"
export JSON_API_PORT="${JSON_API_PORT}"
export DEV_SECRET="${DEV_SECRET}"
export ERC20_PKG_ID="${ERC20_PKG_ID}"
export ISSUER_PARTY="${ISSUER_PARTY}"
export ALICE_PARTY="${ALICE_PARTY}"
export BOB_PARTY="${BOB_PARTY}"
export TOKEN_ISSUER="${TOKEN_ISSUER}"
export TOKEN_ALICE="${TOKEN_ALICE}"
export TOKEN_BOB="${TOKEN_BOB}"
export TOKEN_ISSUER_ALICE="${TOKEN_ISSUER_ALICE}"
export TOKEN="${TOKEN}"
EOF

log "Environment exports written to ${ENV_FILE}"
log "Bootstrap complete."
