# Deployment Guide

This guide covers how to deploy the Canton-EVM Token Bridge to GitHub and manage releases for multiple clients.

## Table of Contents

1. [Repository Structure](#repository-structure)
2. [Branching Strategy](#branching-strategy)
3. [Initial Deployment (Wayfinder)](#initial-deployment-wayfinder)
4. [Adding New Client Bridges](#adding-new-client-bridges)
5. [Release Process](#release-process)
6. [CI/CD Considerations](#cicd-considerations)

---

## Repository Structure

```
canton-erc20/
├── .github/
│   ├── CODEOWNERS              # Code ownership for reviews
│   ├── pull_request_template.md
│   └── workflows/              # GitHub Actions (future)
│
├── daml/
│   ├── multi-package.yaml      # Workspace config
│   │
│   │   # Core (shared by all clients)
│   ├── common/
│   ├── cip56-token/
│   ├── bridge-core/
│   │
│   │   # Client-specific (independent)
│   ├── bridge-wayfinder/       # ✅ v1.0.0
│   ├── bridge-usdc/            # 🚧 Development
│   ├── bridge-cbtc/            # 🚧 Development
│   └── bridge-generic/         # 🚧 Development
│
├── docs/
├── scripts/
├── CHANGELOG.md
├── DEPLOYMENT.md               # This file
└── README.md
```

---

## Branching Strategy

### Branch Types

| Branch | Purpose | Protected |
|--------|---------|-----------|
| `main` | Production-ready code | ✅ Yes |
| `develop` | Integration branch | ✅ Yes |
| `feature/*` | New features | No |
| `fix/*` | Bug fixes | No |
| `release/*` | Release preparation | ✅ Yes |

### Workflow

```
main ◄──────────────────────────────────────────────────────────────┐
  │                                                                  │
  │  (hotfix)                                                        │
  │ ◄──────────────────────────────────────────────────────┐        │
  │                                                         │        │
  ▼                                                         │        │
develop ◄───────────────────────────────────────────────────┼────────┤
  │                                                         │        │
  ├── feature/usdc-bridge ────────────────────────────────►─┘        │
  │                                                                  │
  ├── feature/cbtc-bridge ────────────────────────────────►─┘        │
  │                                                                  │
  └── release/v1.1.0 ────────────────────────────────────────────────┘
```

---

## Initial Deployment (Wayfinder)

### Step 1: Clean and Verify Build

```bash
# Clean all build artifacts
./scripts/clean-all.sh --deep

# Rebuild everything
./scripts/build-all.sh

# Run all tests
./scripts/test-all.sh
```

### Step 2: Stage Changes

```bash
cd /Users/s3b/Dev/canton-erc20

# Check status
git status

# Stage core infrastructure
git add daml/common/
git add daml/cip56-token/
git add daml/bridge-core/
git add daml/multi-package.yaml

# Stage Wayfinder bridge
git add daml/bridge-wayfinder/

# Stage documentation
git add README.md
git add CHANGELOG.md
git add DEPLOYMENT.md
git add docs/

# Stage GitHub config
git add .github/
git add .gitignore
```

### Step 3: Commit with Conventional Commits

```bash
# Commit core infrastructure
git commit -m "feat(core): add CIP-56 token standard and bridge infrastructure

- Add common types (TokenMeta, EvmAddress, ChainRef)
- Implement CIP56Manager with nonconsuming Mint/Burn
- Implement CIP56Holding with privacy-preserving transfers
- Add LockedAsset for async transfer pattern
- Implement ComplianceRules and ComplianceProof
- Add MintProposal, MintAuthorization, RedeemRequest, BurnEvent

BREAKING CHANGE: CIP56Manager.Mint and Burn are now nonconsuming"

# Commit Wayfinder bridge
git commit -m "feat(wayfinder): add production-ready PRIME token bridge

- Add WayfinderBridgeConfig template
- Define primeMetadata (ERC20: 0x28d38df637db75533bd3f71426f3410a82041544)
- Implement full E2E test suite
- Add comprehensive TESTING.md documentation

Closes #XXX"

# Commit documentation
git commit -m "docs: add deployment guide and changelog

- Add CHANGELOG.md with v1.0.0 release notes
- Add DEPLOYMENT.md with branching strategy
- Update README.md with production status
- Add CODEOWNERS and PR template"
```

### Step 4: Tag Release

```bash
# Create annotated tag
git tag -a v1.0.0 -m "Release v1.0.0 - Wayfinder PRIME Bridge

Production-ready release of the Wayfinder (PRIME) token bridge.

Features:
- CIP-56 compliant token standard
- Privacy-preserving transfers
- Full bridge lifecycle (deposit/withdrawal)
- Comprehensive test suite

EVM Contract: 0x28d38df637db75533bd3f71426f3410a82041544"
```

### Step 5: Push to GitHub

```bash
# Push main branch
git push origin main

# Push tags
git push origin v1.0.0

# Or push all tags
git push origin --tags
```

---

## Adding New Client Bridges

### Example: Adding USDC Bridge

#### 1. Create Feature Branch

```bash
git checkout develop
git pull origin develop
git checkout -b feature/usdc-bridge
```

#### 2. Implement Bridge

```bash
# Copy Wayfinder as template
cp -r daml/bridge-wayfinder daml/bridge-usdc

# Update package name and metadata
# Edit daml/bridge-usdc/daml.yaml
# Edit daml/bridge-usdc/src/USDC/Bridge.daml
```

#### 3. Add to Multi-Package

```yaml
# daml/multi-package.yaml
projects:
  - common
  - cip56-token
  - bridge-core
  - bridge-wayfinder
  - bridge-usdc        # Add new bridge
  # ...
```

#### 4. Build and Test

```bash
./scripts/build-all.sh
./scripts/test-all.sh
```

#### 5. Create PR

```bash
git add daml/bridge-usdc/
git commit -m "feat(usdc): add USDC bridge for Circle xReserve

- Implement USDCBridgeConfig
- Add Circle attestation verification hooks
- Add E2E test suite
- Update multi-package.yaml

Relates to #YYY"

git push origin feature/usdc-bridge
# Create PR on GitHub
```

---

## Release Process

### Version Numbering

```
MAJOR.MINOR.PATCH

1.0.0  - Initial Wayfinder release
1.1.0  - Add USDC bridge
1.2.0  - Add cBTC bridge
2.0.0  - Breaking changes to core
```

### Release Checklist

- [ ] All tests pass (`./scripts/test-all.sh`)
- [ ] CHANGELOG.md updated
- [ ] README.md updated with new status
- [ ] Version bumped in affected `daml.yaml` files
- [ ] PR reviewed and approved
- [ ] Merged to `main`
- [ ] Tag created
- [ ] GitHub Release created with release notes

### Creating a Release

```bash
# Ensure on main and up to date
git checkout main
git pull origin main

# Create release branch (optional, for larger releases)
git checkout -b release/v1.1.0

# Update versions
# ... edit daml.yaml files ...

# Update CHANGELOG
# ... add release notes ...

# Commit
git commit -am "chore(release): prepare v1.1.0"

# Merge to main
git checkout main
git merge release/v1.1.0

# Tag
git tag -a v1.1.0 -m "Release v1.1.0 - USDC Bridge"

# Push
git push origin main --tags
```

---

## CI/CD Considerations

### Recommended GitHub Actions

```yaml
# .github/workflows/ci.yml (future)
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup DAML
        uses: digital-asset/setup-daml@v1
        with:
          version: '2.10.2'
      
      - name: Build
        run: ./scripts/build-all.sh
      
      - name: Test
        run: ./scripts/test-all.sh
```

### Branch Protection Rules

For `main` and `develop`:

- ✅ Require pull request reviews (1-2 approvers)
- ✅ Require status checks to pass
- ✅ Require branches to be up to date
- ✅ Require CODEOWNERS review
- ✅ Do not allow force pushes

---

## Quick Reference

### Common Commands

```bash
# Build everything
./scripts/build-all.sh

# Test everything
./scripts/test-all.sh

# Clean build artifacts
./scripts/clean-all.sh --deep

# Test specific package
cd daml/bridge-wayfinder
daml script --dar .daml/dist/bridge-wayfinder-1.0.0.dar \
  --script-name Wayfinder.Test:testWayfinderBridge --ide-ledger
```

### Commit Message Format

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `style`

Scopes: `core`, `wayfinder`, `usdc`, `cbtc`, `generic`, `docs`, `ci`

