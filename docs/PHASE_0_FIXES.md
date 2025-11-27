# Phase 0 Fixes and Corrections

**Date**: November 25, 2024  
**Status**: Resolved  
**Affects**: Phase 0 Quick Start Guide

---

## Issues Found and Fixed

### 1. Invalid `--target` Build Option

**Issue**: The `daml.yaml` files in the Phase 0 Quick Start guide included `build-options: --target=2.1`, which is not compatible with Daml SDK 2.10.2.

**Error Message**:
```
option --target: Unknown Daml-LF version: 1.14, 1.15 (default), 1.17, 1.dev
```

**Root Cause**: Daml SDK 2.10.2 only supports Daml-LF versions 1.14, 1.15 (default), 1.17, and 1.dev. The `--target=2.1` option is invalid.

**Solution**: Remove the `build-options` section from all `daml.yaml` files. The SDK will automatically use the default LF version (1.15).

**Files Fixed**:
- `canton-erc20/daml/common/daml.yaml`
- `canton-erc20/daml/cip56-token/daml.yaml`
- `canton-erc20/daml/bridge-core/daml.yaml`
- `canton-erc20/daml/bridge-usdc/daml.yaml`
- `canton-erc20/daml/bridge-cbtc/daml.yaml`
- `canton-erc20/daml/bridge-generic/daml.yaml`
- `canton-erc20/daml/dvp/daml.yaml`
- `canton-erc20/daml/integration-tests/daml.yaml`
- `canton-erc20/docs/PHASE_0_QUICKSTART.md` (documentation updated)

**Correct `daml.yaml` Format**:
```yaml
name: common
version: 1.0.0
sdk-version: 2.10.2

source: src
dependencies:
  - daml-prim
  - daml-stdlib
  - daml-script

# No build-options needed - uses default LF version
```

---

### 2. Incorrect `deriving` Clause Syntax

**Issue**: The `deriving` clauses in `Common.Types` were not properly indented.

**Error Message**:
```
parse error on input 'deriving'
```

**Root Cause**: In Daml, `deriving` clauses must be indented as part of the `data` declaration.

**Solution**: Indent `deriving` clauses with proper spacing.

**Before** (incorrect):
```daml
data TokenMeta = TokenMeta with
  name     : Text
  symbol   : Text
  decimals : Int
  deriving (Eq, Show)  -- Wrong indentation
```

**After** (correct):
```daml
data TokenMeta = TokenMeta with
  name     : Text
  symbol   : Text
  decimals : Int
    deriving (Eq, Show)  -- Properly indented
```

**File Fixed**: `canton-erc20/daml/common/src/Common/Types.daml`

---

### 3. Missing Import in `Common.Utils`

**Issue**: The `Common.Utils` module used `DA.Text` functions without importing the module.

**Error Message**:
```
Not in scope: 'DA.Text.length'
No module named 'DA.Text' is imported.
```

**Root Cause**: Missing import statement for `DA.Text` module.

**Solution**: Add qualified import for `DA.Text`.

**Before** (incorrect):
```daml
module Common.Utils where

import DA.Assert (assertMsg)
import Common.Types

isValidEvmAddress : Text -> Bool
isValidEvmAddress addr =
  let len = DA.Text.length addr  -- Module not imported!
  in len == 42 && DA.Text.take 2 addr == "0x"
```

**After** (correct):
```daml
module Common.Utils where

import DA.Text qualified as Text
import Common.Types

isValidEvmAddress : Text -> Bool
isValidEvmAddress addr =
  let len = Text.length addr
  in len == 42 && Text.take 2 addr == "0x"
```

**File Fixed**: `canton-erc20/daml/common/src/Common/Utils.daml`

---

### 4. Incorrect Use of `assertMsg` in Pure Functions

**Issue**: The validation helper functions attempted to use `assertMsg` (which returns `Action ()`) in pure boolean functions.

**Error Message**:
```
Couldn't match expected type 'Bool' with actual type 'm1 ()'
```

**Root Cause**: `assertMsg` is an action that must be used within a `do` block in templates/choices, not in pure functions.

**Solution**: Replace with pure boolean checks and provide alternative validation functions.

**Before** (incorrect):
```daml
validateAmount : Decimal -> Text -> Bool
validateAmount amount msg =
  assertMsg msg (amount > 0.0)  -- assertMsg is an action, not a Bool!
```

**After** (correct):
```daml
-- Pure boolean check
isValidAmount : Decimal -> Bool
isValidAmount amount = amount > 0.0

-- For use in templates/choices (with assertMsg):
-- assertMsg "amount must be positive" (isValidAmount amount)

-- Alternative with error message for scripts
validateEvmAddress : Text -> Either Text EvmAddress
validateEvmAddress addr =
  if isValidEvmAddress addr
  then Right (EvmAddress addr)
  else Left ("Invalid EVM address: " <> addr)
```

**File Fixed**: `canton-erc20/daml/common/src/Common/Utils.daml`

---

## Build Instructions (Corrected)

### Building Individual Packages

To build a single package without multi-package mode:

```bash
cd canton-erc20/daml/common
daml build --enable-multi-package=no
```

This bypasses the multi-package system and builds just the current package.

### Expected Output

```bash
2025-11-25 22:06:56.53 [INFO]  [build]
Compiling common to a DAR.

2025-11-25 22:06:57.25 [INFO]  [build]
Created .daml/dist/common-1.0.0.dar
```

### Verify Build Success

```bash
ls -lh daml/common/.daml/dist/
# Should show: common-1.0.0.dar (~242K)
```

---

## Updated `Common.Utils` API

The corrected `Common.Utils` module provides:

### Pure Boolean Checks (for use anywhere)
```daml
isValidAmount : Decimal -> Bool
-- Returns True if amount > 0

hasSufficientBalance : Decimal -> Decimal -> Bool
-- Returns True if balance >= amount

isValidEvmAddress : Text -> Bool
-- Returns True if address is valid (0x + 40 hex chars)
```

### Optional Constructors
```daml
mkEvmAddress : Text -> Optional EvmAddress
-- Returns Some address if valid, None otherwise
```

### Either-Based Validation (with error messages)
```daml
validateEvmAddress : Text -> Either Text EvmAddress
-- Returns Right address if valid, Left error message otherwise
```

### Usage in Templates

```daml
template MyTemplate
  where
    signatory issuer
    
    choice MyChoice : ()
      with
        amount : Decimal
        evmAddr : Text
      controller issuer
      do
        -- Use pure checks with assertMsg
        assertMsg "Amount must be positive" (isValidAmount amount)
        assertMsg "Balance insufficient" (hasSufficientBalance balance amount)
        
        -- Validate EVM address
        case mkEvmAddress evmAddr of
          Some addr -> do
            -- Use valid address
            pure ()
          None -> abort "Invalid EVM address"
```

---

## Testing

After applying all fixes, the `common` package builds successfully:

```bash
cd canton-erc20/daml/common
daml build --enable-multi-package=no
# ✅ Created .daml/dist/common-1.0.0.dar

daml test --enable-multi-package=no
# ✅ All 0 tests passed (no tests defined yet)
```

---

## Next Steps

1. ✅ Common package builds successfully
2. ⏭️ Create placeholder modules for other packages (cip56-token, bridge-core, etc.)
3. ⏭️ Build all packages in dependency order
4. ⏭️ Continue with Phase 1 (CIP-56 Token implementation)

---

## Summary of Changes

| File | Issue | Fix |
|------|-------|-----|
| All `daml.yaml` files | Invalid `--target=2.1` | Removed `build-options` section |
| `Common.Types.daml` | `deriving` syntax error | Indented `deriving` clauses properly |
| `Common.Utils.daml` | Missing import | Added `import DA.Text qualified as Text` |
| `Common.Utils.daml` | `assertMsg` type error | Replaced with pure boolean functions |
| `PHASE_0_QUICKSTART.md` | Documentation errors | Updated examples to remove `--target` |

---

## Verification Checklist

- [x] All `daml.yaml` files have no `build-options: --target` entries
- [x] `Common.Types.daml` compiles without errors
- [x] `Common.Utils.daml` compiles without errors
- [x] `common` package builds successfully
- [x] `.daml/dist/common-1.0.0.dar` is created
- [x] Documentation updated to reflect correct syntax

---

## Additional Notes

### Multi-Package Build Behavior

When building from within a package directory (e.g., `daml/common/`), the build system looks for `multi-package.yaml` in that directory. To avoid this:

**Option 1**: Disable multi-package mode
```bash
cd daml/common
daml build --enable-multi-package=no
```

**Option 2**: Build all packages from workspace root
```bash
cd daml
daml build --all
# This uses the multi-package.yaml in the daml/ directory
```

For Phase 0 development, **Option 1** is recommended for testing individual packages.

---

## References

- [Daml Data Types Documentation](https://docs.daml.com/daml/intro/3_Data.html)
- [Daml Standard Library](https://docs.daml.com/daml/stdlib/)
- [Multi-Package Projects](https://docs.daml.com/tools/assistant.html#multi-package-project-files)

---

**Status**: All Phase 0 blocking issues resolved. Ready to proceed with creating placeholder packages.