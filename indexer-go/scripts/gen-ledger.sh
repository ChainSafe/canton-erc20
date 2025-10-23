#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROTO_DIR="${ROOT_DIR}/proto"
OUT_DIR="${ROOT_DIR}/gen"

CANDIDATE_VERSION=$(daml version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
if [ -z "${CANDIDATE_VERSION}" ] && [ -z "${DAML_SDK_VERSION:-}" ]; then
  echo "Unable to determine Daml SDK version. Set DAML_SDK_VERSION environment variable." >&2
  exit 1
fi
DAML_SDK_VERSION="${DAML_SDK_VERSION:-${CANDIDATE_VERSION}}"
CANTON_JAR="${HOME}/.daml/sdk/${DAML_SDK_VERSION}/canton/canton.jar"

if [ ! -f "${CANTON_JAR}" ]; then
  echo "Cannot locate canton.jar at ${CANTON_JAR}. Set DAML_SDK_VERSION or install the Daml SDK." >&2
  exit 1
fi

if ! command -v protoc >/dev/null; then
  echo "protoc is required. Please install Protocol Buffers compiler." >&2
  exit 1
fi

if ! command -v protoc-gen-go >/dev/null; then
  echo "protoc-gen-go is required. Install via 'go install google.golang.org/protobuf/cmd/protoc-gen-go@latest'." >&2
  exit 1
fi

if ! command -v protoc-gen-go-grpc >/dev/null; then
  echo "protoc-gen-go-grpc is required. Install via 'go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest'." >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"

# Ensure google protos required by the ledger API are available
if [ ! -f "${PROTO_DIR}/google/rpc/status.proto" ]; then
  echo "[gen-ledger] extracting google protos from ${CANTON_JAR}"
  (cd "${PROTO_DIR}" && jar xf "${CANTON_JAR}" \
    google/rpc/status.proto \
    google/rpc/error_details.proto \
    google/rpc/code.proto \
    google/protobuf/any.proto \
    google/protobuf/empty.proto \
    google/protobuf/timestamp.proto \
    google/protobuf/wrappers.proto)
fi

# Ensure go_package options point to the local module
python3 - <<'PY'
from pathlib import Path
root = Path('${PROTO_DIR}/com/daml/ledger/api/v1')
target = 'option go_package = "canton-erc20/indexer-go/gen/com/daml/ledger/api/v1;apiv1";\n'
for path in root.glob('*.proto'):
    text = path.read_text()
    if 'option go_package' not in text:
        pkg_marker = 'package com.daml.ledger.api.v1;\n'
        if pkg_marker in text:
            text = text.replace(pkg_marker, pkg_marker + target, 1)
            path.write_text(text)
    elif 'canton-erc20/indexer-go' not in text:
        text = text.replace('github.com/ChainSafe/canton-erc20/indexer-go/gen/com/daml/ledger/api/v1;apiv1', 'canton-erc20/indexer-go/gen/com/daml/ledger/api/v1;apiv1')
        path.write_text(text)
PY

protoc \
  --proto_path="${PROTO_DIR}" \
  --proto_path="${PROTO_DIR}/com" \
  --proto_path="${PROTO_DIR}/google" \
  --go_out=paths=source_relative:"${OUT_DIR}" \
  --go-grpc_out=paths=source_relative:"${OUT_DIR}" \
  $(find "${PROTO_DIR}/com/daml/ledger/api/v1" -name '*.proto')

echo "Generated Go stubs in ${OUT_DIR}"
