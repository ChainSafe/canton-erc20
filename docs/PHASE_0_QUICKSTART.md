# Phase 0 Quick Start Guide

**Goal**: Set up multi-package workspace and migrate existing code  
**Duration**: Week 1-2  
**Prerequisites**: Daml SDK 2.10.2, Git

---

## Overview

This guide walks you through Phase 0 of the Canton-ERC20 bridge implementation: restructuring the repository into a multi-package workspace while preserving existing functionality.

---

## Week 1: Workspace Setup

### Step 1: Backup Current Code

Always create a backup before major restructuring:

```bash
# Create backup branch
git checkout -b backup-pre-phase0
git push origin backup-pre-phase0

# Create feature branch
git checkout main
git pull
git checkout -b feature/phase0-multi-package
```

### Step 2: Create Package Directory Structure

```bash
cd canton-erc20/daml

# Create package directories
mkdir -p common/{src,test}
mkdir -p cip56-token/{src,test,Scripts}
mkdir -p bridge-core/{src,test,Scripts}
mkdir -p bridge-usdc/{src,test,Scripts}
mkdir -p bridge-cbtc/{src,test,Scripts}
mkdir -p bridge-generic/{src,test,Scripts}
mkdir -p dvp/{src,test,Scripts}
mkdir -p integration-tests

echo "✓ Package directories created"
```

### Step 3: Create Multi-Package Configuration

**Important Note**: The `daml.yaml` examples below do NOT include `build-options: --target=2.1` because this is incompatible with Daml SDK 2.10.2. The SDK only supports LF versions 1.14, 1.15 (default), 1.17, and 1.dev. Using `--target=2.1` will cause build errors.

Create `daml/multi-package.yaml`:

```yaml
# Multi-package workspace configuration
projects:
  - common
  - cip56-token
  - bridge-core
  - bridge-usdc
  - bridge-cbtc
  - bridge-generic
  - dvp
  - integration-tests
```

### Step 4: Create Package Configurations

#### Common Package

Create `daml/common/daml.yaml`:

```yaml
name: common
version: 1.0.0
sdk-version: 2.10.2

source: src
dependencies:
  - daml-prim
  - daml-stdlib
  - daml-script
```

#### CIP56 Token Package

Create `daml/cip56-token/daml.yaml`:

```yaml
name: cip56-token
version: 1.0.0
sdk-version: 2.10.2

source: src
dependencies:
  - daml-prim
  - daml-stdlib
  - daml-script

data-dependencies:
  - ../common/.daml/dist/common-1.0.0.dar
```

#### Bridge Core Package

Create `daml/bridge-core/daml.yaml`:

```yaml
name: bridge-core
version: 1.0.0
sdk-version: 2.10.2

source: src
dependencies:
  - daml-prim
  - daml-stdlib
  - daml-script

data-dependencies:
  - ../common/.daml/dist/common-1.0.0.dar
  - ../cip56-token/.daml/dist/cip56-token-1.0.0.dar
```

#### Bridge USDC Package

Create `daml/bridge-usdc/daml.yaml`:

```yaml
name: bridge-usdc
version: 1.0.0
sdk-version: 2.10.2

source: src
dependencies:
  - daml-prim
  - daml-stdlib
  - daml-script

data-dependencies:
  - ../common/.daml/dist/common-1.0.0.dar
  - ../cip56-token/.daml/dist/cip56-token-1.0.0.dar
  - ../bridge-core/.daml/dist/bridge-core-1.0.0.dar
```

#### Bridge CBTC Package

Create `daml/bridge-cbtc/daml.yaml`:

```yaml
name: bridge-cbtc
version: 1.0.0
sdk-version: 2.10.2

source: src
dependencies:
  - daml-prim
  - daml-stdlib
  - daml-script

data-dependencies:
  - ../common/.daml/dist/common-1.0.0.dar
  - ../cip56-token/.daml/dist/cip56-token-1.0.0.dar
  - ../bridge-core/.daml/dist/bridge-core-1.0.0.dar
```

#### Bridge Generic Package

Create `daml/bridge-generic/daml.yaml`:

```yaml
name: bridge-generic
version: 1.0.0
sdk-version: 2.10.2

source: src
dependencies:
  - daml-prim
  - daml-stdlib
  - daml-script

data-dependencies:
  - ../common/.daml/dist/common-1.0.0.dar
  - ../cip56-token/.daml/dist/cip56-token-1.0.0.dar
  - ../bridge-core/.daml/dist/bridge-core-1.0.0.dar
```

#### DvP Package

Create `daml/dvp/daml.yaml`:

```yaml
name: dvp
version: 1.0.0
sdk-version: 2.10.2

source: src
dependencies:
  - daml-prim
  - daml-stdlib
  - daml-script

data-dependencies:
  - ../common/.daml/dist/common-1.0.0.dar
  - ../cip56-token/.daml/dist/cip56-token-1.0.0.dar
```

#### Integration Tests Package

Create `daml/integration-tests/daml.yaml`:

```yaml
name: integration-tests
version: 1.0.0
sdk-version: 2.10.2

source: .
dependencies:
  - daml-prim
  - daml-stdlib
  - daml-script

data-dependencies:
  - ../common/.daml/dist/common-1.0.0.dar
  - ../cip56-token/.daml/dist/cip56-token-1.0.0.dar
  - ../bridge-core/.daml/dist/bridge-core-1.0.0.dar
  - ../bridge-usdc/.daml/dist/bridge-usdc-1.0.0.dar
  - ../bridge-cbtc/.daml/dist/bridge-cbtc-1.0.0.dar
  - ../bridge-generic/.daml/dist/bridge-generic-1.0.0.dar
  - ../dvp/.daml/dist/dvp-1.0.0.dar
```

### Step 5: Test Initial Build

```bash
# Try building common package first
cd common
daml build

# Should create: .daml/dist/common-1.0.0.dar
ls -la .daml/dist/

cd ..
echo "✓ Common package builds successfully"
```

---

## Week 2: Code Migration

### Step 1: Migrate Common Types

Create `daml/common/src/Common/Types.daml`:

```daml
module Common.Types where

-- Token metadata (from ERC20.Types)
data TokenMeta = TokenMeta with
  name     : Text
  symbol   : Text
  decimals : Int
  deriving (Eq, Show)

-- Chain reference for cross-chain events
data ChainRef = ChainRef with
  chainName : Text
  eventId   : Text
  deriving (Eq, Show)

-- Bridge direction
data BridgeDirection = ToCanton | ToEvm
  deriving (Eq, Show)

-- EVM address type
newtype EvmAddress = EvmAddress with
  value : Text
  deriving (Eq, Show)

-- Extended metadata for CIP-56 compliance
data ExtendedMetadata = ExtendedMetadata with
  name           : Text
  symbol         : Text
  decimals       : Int
  isin           : Optional Text
  dtiCode        : Optional Text
  regulatoryInfo : Optional Text
  deriving (Eq, Show)

-- Convert basic to extended metadata
toExtendedMetadata : TokenMeta -> ExtendedMetadata
toExtendedMetadata tm = ExtendedMetadata with
  name           = tm.name
  symbol         = tm.symbol
  decimals       = tm.decimals
  isin           = None
  dtiCode        = None
  regulatoryInfo = None

-- Convert extended to basic metadata
toBasicMetadata : ExtendedMetadata -> TokenMeta
toBasicMetadata em = TokenMeta with
  name     = em.name
  symbol   = em.symbol
  decimals = em.decimals
```

Create `daml/common/src/Common/Utils.daml`:

```daml
module Common.Utils where

import DA.Assert (assertMsg)
import Common.Types

-- Validation helpers
validateAmount : Decimal -> Text -> Bool
validateAmount amount msg = 
  assertMsg msg (amount > 0.0)

validateBalance : Decimal -> Decimal -> Text -> Bool
validateBalance balance amount msg =
  assertMsg msg (balance >= amount)

-- EVM address validation (basic)
isValidEvmAddress : Text -> Bool
isValidEvmAddress addr =
  let len = DA.Text.length addr
  in len == 42 && DA.Text.take 2 addr == "0x"

-- Create EVM address with validation
mkEvmAddress : Text -> Optional EvmAddress
mkEvmAddress addr =
  if isValidEvmAddress addr
  then Some (EvmAddress addr)
  else None
```

Build common package:

```bash
cd daml/common
daml build
daml test  # Should show 0 tests (we'll add tests later)
cd ../..
```

### Step 2: Migrate Bridge Core

Copy existing bridge templates to bridge-core:

```bash
# Copy existing bridge files as starting point
cp daml/ERC20/Bridge/Types.daml daml/bridge-core/src/
cp daml/ERC20/Bridge/Contracts.daml daml/bridge-core/src/
cp daml/ERC20/Bridge/Script.daml daml/bridge-core/Scripts/
```

Update `daml/bridge-core/src/Types.daml` to use Common.Types:

```daml
module Bridge.Types where

-- Re-export common types for convenience
import Common.Types

-- Bridge-specific types can be added here
-- (ChainRef, BridgeDirection, EvmAddress are now in Common.Types)
```

Update `daml/bridge-core/src/Contracts.daml` imports:

```daml
module Bridge.Contracts where

import DA.Assert (assertMsg)
import Common.Types
import Bridge.Types
-- Note: We'll add CIP56 token import in Phase 1
-- For now, keep the basic Token import from old structure
```

Build bridge-core:

```bash
cd daml/cip56-token
# Create placeholder for now
echo "module CIP56.Token where" > src/Token.daml
daml build
cd ../bridge-core
daml build
cd ../..
```

### Step 3: Create Placeholder Packages

For packages we'll implement later, create minimal placeholders:

**USDC Placeholder** (`daml/bridge-usdc/src/USDC/Bridge.daml`):

```daml
module USDC.Bridge where

-- USDC bridge implementation
-- To be implemented in Phase 3
```

**CBTC Placeholder** (`daml/bridge-cbtc/src/CBTC/Bridge.daml`):

```daml
module CBTC.Bridge where

-- CBTC bridge implementation
-- To be implemented in Phase 4
```

**Generic Placeholder** (`daml/bridge-generic/src/Generic/Bridge.daml`):

```daml
module Generic.Bridge where

-- Generic ERC20 bridge implementation
-- To be implemented in Phase 5
```

**DvP Placeholder** (`daml/dvp/src/DvP/Settlement.daml`):

```daml
module DvP.Settlement where

-- Delivery vs Payment settlement
-- To be implemented in Phase 6
```

Build all packages:

```bash
cd daml

# Build in dependency order
cd common && daml build && cd ..
cd cip56-token && daml build && cd ..
cd bridge-core && daml build && cd ..
cd bridge-usdc && daml build && cd ..
cd bridge-cbtc && daml build && cd ..
cd bridge-generic && daml build && cd ..
cd dvp && daml build && cd ..

echo "✓ All packages build successfully"
```

### Step 4: Update Build Scripts

Update `canton-erc20/scripts/build-all-packages.sh`:

```bash
#!/bin/bash
set -e

echo "Building all Daml packages..."

cd daml

# Build in dependency order
packages=(
  "common"
  "cip56-token"
  "bridge-core"
  "bridge-usdc"
  "bridge-cbtc"
  "bridge-generic"
  "dvp"
  "integration-tests"
)

for pkg in "${packages[@]}"; do
  echo "Building $pkg..."
  cd "$pkg"
  daml build
  cd ..
  echo "✓ $pkg built successfully"
done

echo "✓ All packages built successfully!"
```

Make it executable:

```bash
chmod +x scripts/build-all-packages.sh
```

Test the build script:

```bash
./scripts/build-all-packages.sh
```

### Step 5: Update Bootstrap Script

Update `canton-erc20/scripts/bootstrap.sh` to use new structure:

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Canton ERC-20 Bootstrap (Phase 0) ==="

# Build all packages
echo "Building all Daml packages..."
"$SCRIPT_DIR/build-all-packages.sh"

# Start Canton Sandbox
echo "Starting Canton Sandbox..."
SANDBOX_PORT=${SANDBOX_PORT:-6865}

# Check if sandbox is already running
if lsof -Pi :$SANDBOX_PORT -sTCP:LISTEN -t >/dev/null ; then
    echo "Sandbox already running on port $SANDBOX_PORT"
else
    echo "Starting new sandbox on port $SANDBOX_PORT..."
    # For Phase 0, use bridge-core package
    daml start --sandbox-port=$SANDBOX_PORT \
               --dar="$PROJECT_ROOT/daml/bridge-core/.daml/dist/bridge-core-1.0.0.dar" &
    
    SANDBOX_PID=$!
    echo $SANDBOX_PID > log/sandbox-bootstrap.pid
    echo "Sandbox started (PID: $SANDBOX_PID)"
    
    # Wait for sandbox to be ready
    sleep 5
fi

# Generate dev-env.sh
echo "Generating dev-env.sh..."
cat > "$PROJECT_ROOT/dev-env.sh" << EOF
# Generated by bootstrap.sh - $(date)
export SANDBOX_PORT=$SANDBOX_PORT
export LEDGER_HOST=localhost
export LEDGER_PORT=$SANDBOX_PORT

# Package information
export COMMON_PKG_ID="$(daml damlc inspect-dar "$PROJECT_ROOT/daml/common/.daml/dist/common-1.0.0.dar" | grep "package-id" | awk '{print $2}')"
export BRIDGE_CORE_PKG_ID="$(daml damlc inspect-dar "$PROJECT_ROOT/daml/bridge-core/.daml/dist/bridge-core-1.0.0.dar" | grep "package-id" | awk '{print $2}')"

echo "Canton ERC-20 environment loaded"
echo "  SANDBOX_PORT=$SANDBOX_PORT"
echo "  COMMON_PKG_ID=$COMMON_PKG_ID"
echo "  BRIDGE_CORE_PKG_ID=$BRIDGE_CORE_PKG_ID"
EOF

echo "✓ Bootstrap complete!"
echo ""
echo "Next steps:"
echo "  1. source dev-env.sh"
echo "  2. cd indexer-go && go run ./cmd/indexer"
echo "  3. cd middleware && npm start"
```

### Step 6: Test Everything

```bash
# Clean any previous state
rm -rf daml/*/.daml/dist

# Run bootstrap
./scripts/bootstrap.sh

# Source environment
source dev-env.sh

# Verify environment variables
echo "SANDBOX_PORT: $SANDBOX_PORT"
echo "COMMON_PKG_ID: $COMMON_PKG_ID"
echo "BRIDGE_CORE_PKG_ID: $BRIDGE_CORE_PKG_ID"

# Test that sandbox is running
daml ledger list-parties --host localhost --port $SANDBOX_PORT

echo "✓ Phase 0 setup complete!"
```

---

## Verification Checklist

- [ ] All package directories created
- [ ] Multi-package.yaml configured
- [ ] Each package has daml.yaml
- [ ] Common package builds
- [ ] All packages build in order
- [ ] build-all-packages.sh works
- [ ] bootstrap.sh updated and works
- [ ] dev-env.sh generated correctly
- [ ] Canton Sandbox starts successfully
- [ ] Environment variables set correctly

---

## Common Issues & Solutions

### Issue: "Cannot find package"

**Symptom**: Build fails with "Could not find package X"

**Solution**: Build packages in dependency order:
```bash
cd daml/common && daml build && cd ..
cd daml/cip56-token && daml build && cd ..
# etc...
```

### Issue: "Package ID mismatch"

**Symptom**: data-dependencies complain about wrong package ID

**Solution**: Rebuild the dependency package and update the .dar reference:
```bash
cd daml/common
daml clean
daml build
# Check the generated .dar file name
ls .daml/dist/
```

### Issue: "Port already in use"

**Symptom**: Sandbox won't start, port 6865 busy

**Solution**: Kill existing sandbox:
```bash
lsof -ti:6865 | xargs kill -9
# Or use a different port
export SANDBOX_PORT=6866
./scripts/bootstrap.sh
```

### Issue: "Unknown Daml-LF version" or "--target" error

**Symptom**: Build fails with `option --target: Unknown Daml-LF version: 1.14, 1.15 (default), 1.17, 1.dev`

**Solution**: Remove `build-options: --target=2.1` from your `daml.yaml` files. This option is not compatible with Daml SDK 2.10.2. The SDK will use the default LF version (1.15) automatically.

```yaml
# WRONG - causes error
build-options:
  - --target=2.1

# CORRECT - omit build-options or use valid LF version
# (no build-options section needed)
```

### Issue: "daml: command not found"

**Symptom**: daml commands don't work

**Solution**: Install Daml SDK:
```bash
# macOS/Linux
curl -sSL https://get.daml.com/ | sh

# Verify installation
daml version  # Should show 2.10.2
```

---

## Next Steps

Once Phase 0 is complete:

1. **Commit your changes**:
   ```bash
   git add .
   git commit -m "Phase 0: Multi-package workspace setup"
   git push origin feature/phase0-multi-package
   ```

2. **Create Pull Request**:
   - Review changes with team
   - Ensure all checks pass
   - Merge to main

3. **Begin Phase 1**:
   - See [IMPLEMENTATION_ROADMAP.md](./IMPLEMENTATION_ROADMAP.md)
   - Start implementing CIP-56 token standard
   - Focus on `daml/cip56-token/` package

---

## Reference

### Package Structure Summary

```
daml/
├── multi-package.yaml              # Workspace config
├── common/                         # Shared types and utilities
│   ├── daml.yaml
│   ├── src/
│   │   ├── Common/
│   │   │   ├── Types.daml
│   │   │   └── Utils.daml
│   └── .daml/dist/                # Built DAR
├── cip56-token/                    # CIP-56 token (Phase 1)
├── bridge-core/                    # Core bridge (Phase 2)
├── bridge-usdc/                    # USDC bridge (Phase 3)
├── bridge-cbtc/                    # CBTC bridge (Phase 4)
├── bridge-generic/                 # Generic bridge (Phase 5)
├── dvp/                            # DvP settlement (Phase 6)
└── integration-tests/              # E2E tests (Phase 7)
```

### Key Commands

```bash
# Build all packages
./scripts/build-all-packages.sh

# Bootstrap environment
./scripts/bootstrap.sh
source dev-env.sh

# Build specific package
cd daml/common && daml build

# Clean and rebuild
daml clean && daml build

# Test a package
daml test

# Inspect DAR
daml damlc inspect-dar <package>.dar
```

### Useful Links

- [Daml Multi-Package Documentation](https://docs.daml.com/tools/assistant.html#multi-package-project-files)
- [Data Dependencies Guide](https://docs.daml.com/daml/reference/packages.html#data-dependencies)
- [Daml Build System](https://docs.daml.com/tools/assistant.html#project-config-file-daml-yaml)
- [Phase 1 Guide](./IMPLEMENTATION_ROADMAP.md#phase-1-cip-56-token-standard-week-3-5)

---

## Support

For questions or issues:
1. Check [Common Issues](#common-issues--solutions) above
2. Review [DAML_ARCHITECTURE_PROPOSAL.md](./DAML_ARCHITECTURE_PROPOSAL.md)
3. Consult [Daml Documentation](https://docs.daml.com/)
4. Ask the team in daily standup