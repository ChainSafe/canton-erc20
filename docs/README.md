# Canton-ERC20 Bridge Documentation

Welcome to the Canton-ERC20 bridge documentation. This guide will help you navigate the available documentation and understand the project architecture.

> **Note**: This repository contains only the DAML smart contracts. The Go middleware is maintained separately by ChainSafe. See [REPOSITORY_CLEANUP.md](./REPOSITORY_CLEANUP.md) for details.

---

## 📚 Documentation Index

### Getting Started

1. **[EXECUTIVE_SUMMARY.md](./EXECUTIVE_SUMMARY.md)** - **START HERE**
   - Overview of current state vs. requirements
   - Recommended architecture approach
   - Implementation timeline
   - Key design patterns
   - Quick answers to common questions

2. **[PHASE_0_QUICKSTART.md](./PHASE_0_QUICKSTART.md)** - **NEXT STEPS**
   - Step-by-step guide for Week 1-2
   - Multi-package workspace setup
   - Code migration instructions
   - Troubleshooting common issues

### Detailed Documentation

3. **[REPOSITORY_CLEANUP.md](./REPOSITORY_CLEANUP.md)** - **MIGRATION INFO**
   - What was removed (Go indexer, Node.js middleware)
   - What was added (new build scripts)
   - Repository structure after cleanup
   - Integration between DAML and Go middleware repos
   - Build and test commands

4. **[DAML_ARCHITECTURE_PROPOSAL.md](./DAML_ARCHITECTURE_PROPOSAL.md)** - **DEEP DIVE**
   - Comprehensive technical design
   - Current state analysis (what exists, what's missing)
   - Gap analysis against SOW requirements
   - Proposed package structure
   - Detailed design patterns
   - Testing strategy
   - Integration points with Go middleware
   - Success criteria

5. **[IMPLEMENTATION_ROADMAP.md](./IMPLEMENTATION_ROADMAP.md)** - **PROJECT PLAN**
   - Visual timeline (18 weeks)
   - Phase-by-phase breakdown
   - Task checklists for each phase
   - Test scripts and deliverables
   - Risk management
   - Progress tracking metrics

### Requirements (SOW Folder)

6. **[sow/BRIDGE_IMPLEMENTATION_PLAN.md](./sow/BRIDGE_IMPLEMENTATION_PLAN.md)**
   - High-level bridge architecture
   - Technology stack
   - Security considerations
   - Implementation phases

7. **[sow/canton-integration.md](./sow/canton-integration.md)**
   - Canton Network specifics
   - Daml Ledger gRPC API integration
   - Event streaming patterns
   - Command submission patterns

8. **[sow/usdc.md](./sow/usdc.md)**
   - USDC bridging requirements
   - Circle xReserve integration
   - CIP-86 compliance

9. **[sow/cbtc.md](./sow/cbtc.md)**
   - CBTC bridging requirements
   - BitSafe vault integration
   - Custody workflows

10. **[sow/evm.md](./sow/evm.md)**
   - Generic ERC20 token bridging
   - EVM chain integration
   - Token mapping

### Architecture & Development

11. **[middleware-bridge-architecture.md](./middleware-bridge-architecture.md)**
    - Repository governance
    - Ledger design patterns
    - Middleware integration layer
    - Validation and testing regimes
    - Canton infrastructure considerations

12. **[dev-setup.md](./dev-setup.md)**
    - Prerequisites (macOS & Linux)
    - Installation steps
    - Repository setup
    - Validation steps

13. **[startup-flow.md](./startup-flow.md)**
    - Starting Canton Sandbox
    - Running test scripts
    - Verification steps
    - **Note**: Go indexer and Node.js middleware sections are deprecated (see REPOSITORY_CLEANUP.md)
    - Starting Canton Sandbox
    - Running Go indexer
    - Running middleware
    - Verification steps

---

## 🚀 Quick Start Path

### For New Team Members

```
1. Read EXECUTIVE_SUMMARY.md (15 min)
   ↓
2. Read REPOSITORY_CLEANUP.md (10 min) - understand repo structure
   ↓
3. Review SOW requirements in sow/ folder (30 min)
   ↓
4. Skim DAML_ARCHITECTURE_PROPOSAL.md (30 min)
   ↓
5. Set up development environment using dev-setup.md (30 min)
   ↓
6. Start Phase 0 using PHASE_0_QUICKSTART.md (1-2 weeks)
```

### For Architects/Tech Leads

```
1. Read EXECUTIVE_SUMMARY.md (15 min)
   ↓
2. Deep dive into DAML_ARCHITECTURE_PROPOSAL.md (1 hour)
   ↓
3. Review IMPLEMENTATION_ROADMAP.md (30 min)
   ↓
4. Review SOW requirements (30 min)
   ↓
5. Validate approach with team
```

### For Project Managers

```
1. Read EXECUTIVE_SUMMARY.md (15 min)
   ↓
2. Review IMPLEMENTATION_ROADMAP.md for timeline (30 min)
   ↓
3. Note milestones and risk management sections
   ↓
4. Set up weekly check-ins per communication plan
```

---

## 📖 Reading Guide by Role

### **DAML Developer**
Priority reading:
1. ✅ DAML_ARCHITECTURE_PROPOSAL.md (Design Patterns section)
2. ✅ PHASE_0_QUICKSTART.md (Implementation guide)
3. ✅ middleware-bridge-architecture.md (Ledger patterns)
4. ✅ IMPLEMENTATION_ROADMAP.md (Phase tasks)

Focus: Template design, testing strategy, Canton privacy model

### **Go Middleware Developer**
Priority reading:
1. ✅ REPOSITORY_CLEANUP.md (Integration between repos)
2. ✅ sow/canton-integration.md (gRPC API)
3. ✅ DAML_ARCHITECTURE_PROPOSAL.md (Integration Points)
4. ✅ sow/BRIDGE_IMPLEMENTATION_PLAN.md (Relayer architecture)

Focus: Event streaming, command submission, state management
Note: Go middleware is in separate ChainSafe repository

### **Full-Stack Engineer**
Priority reading:
1. ✅ EXECUTIVE_SUMMARY.md (Overview)
2. ✅ DAML_ARCHITECTURE_PROPOSAL.md (Complete design)
3. ✅ All SOW documents (Requirements)
4. ✅ IMPLEMENTATION_ROADMAP.md (Tasks)

Focus: End-to-end understanding, integration patterns

### **QA/Test Engineer**
Priority reading:
1. ✅ DAML_ARCHITECTURE_PROPOSAL.md (Testing Strategy)
2. ✅ IMPLEMENTATION_ROADMAP.md (Test scripts per phase)
3. ✅ PHASE_0_QUICKSTART.md (Setup)

Focus: Test coverage, test scripts, verification

---

## 🎯 Key Concepts

### Multi-Package Architecture
The project is structured as multiple Daml packages for modularity:
- `common/` - Shared types and utilities
- `cip56-token/` - CIP-56 compliant token standard
- `bridge-core/` - Reusable bridge infrastructure
- `bridge-usdc/` - USDC-specific (xReserve)
- `bridge-cbtc/` - CBTC-specific (BitSafe)
- `bridge-generic/` - Generic ERC20 support
- `dvp/` - Delivery vs Payment
- `integration-tests/` - End-to-end tests

### CIP-56 Compliance
Canton Improvement Proposal 56 defines the token standard:
- Privacy-preserving transfers
- Multi-step authorization
- Token admin controls
- Receiver authorization
- Compliance hooks

### Testability
**Critical requirement**: All bridge logic must be testable via Daml scripts without the Go middleware running.

### Bridge Pattern
Two-step proposal/acceptance for multi-party consent:
1. Operator proposes action (mint/burn)
2. User accepts with signature
3. Action executes atomically

---

## 📋 Implementation Phases

| Phase | Duration | Focus | Status |
|-------|----------|-------|--------|
| 0: Foundation | Week 1-2 | Multi-package setup | 🔴 Not Started |
| 1: CIP-56 Token | Week 3-5 | Token standard | 🔴 Not Started |
| 2: Bridge Core | Week 6-8 | Reusable bridge | 🔴 Not Started |
| 3: USDC Bridge | Week 9-10 | xReserve integration | 🔴 Not Started |
| 4: CBTC Bridge | Week 11-12 | BitSafe vaults | 🔴 Not Started |
| 5: Generic Bridge | Week 13-14 | Any ERC20 | 🔴 Not Started |
| 6: DvP Settlement | Week 15-16 | Atomic swaps | 🔴 Not Started |
| 7: Integration | Week 17-18 | E2E testing | 🔴 Not Started |

---

## 🛠 Useful Commands

### Development
```bash
# Build all packages
./scripts/build-all.sh

# Run all tests
./scripts/test-all.sh

# Clean build artifacts
./scripts/clean-all.sh

# Build individual package
cd daml/<package>
daml build --enable-multi-package=no

# Run tests for individual package
cd daml/<package>
daml test --enable-multi-package=no

# Run specific script
daml script --dar <package>.dar \
  --script-name Module:scriptName \
  --ledger-host localhost \
  --ledger-port 6865
```

### Verification
```bash
# Check package builds
cd daml/<package> && daml build

# Inspect DAR
daml damlc inspect-dar <package>.dar

# List parties on ledger
daml ledger list-parties \
  --host localhost \
  --port 6865
```

---

## 🔗 External Resources

- [Canton Network](https://www.canton.network/)
- [Daml Documentation](https://docs.daml.com/)
- [CIP-56 Specification](https://www.canton.network/blog/what-is-cip-56)
- [Canton Ledger API Reference](https://docs.daml.com/build/3.3/reference/lapi-proto-docs.html)
- [Circle xReserve](https://www.circle.com/en/cross-chain-transfer-protocol)
- [Digital Asset GitHub](https://github.com/digital-asset/daml)

---

## 📝 Contributing

When adding new documentation:

1. **Keep docs synchronized** with code changes
2. **Update this README** when adding new docs
3. **Use clear headings** and structure
4. **Provide code examples** where relevant
5. **Link between documents** for easy navigation

---

## 🆘 Getting Help

### Documentation Issues
- Check [REPOSITORY_CLEANUP.md](./REPOSITORY_CLEANUP.md) for recent changes
- Check the [Common Issues](./PHASE_0_QUICKSTART.md#common-issues--solutions) section
- Review relevant SOW documents for requirements
- Consult Daml documentation

### Technical Questions
1. Review architecture proposal for design decisions
2. Check implementation roadmap for planned features
3. Ask in daily standup
4. Consult with team tech lead

### Process Questions
1. Review implementation roadmap for phases
2. Check communication plan in roadmap
3. Contact project manager

---

## 📅 Document Version History

| Date | Version | Changes |
|------|---------|---------|
| Jan 2025 | 1.0 | Initial documentation suite created |

---

## 📍 Where to Start

**If you're new to this project**: Start with [EXECUTIVE_SUMMARY.md](./EXECUTIVE_SUMMARY.md)

**If you're ready to code**: Start with [PHASE_0_QUICKSTART.md](./PHASE_0_QUICKSTART.md)

**If you need the full picture**: Read [DAML_ARCHITECTURE_PROPOSAL.md](./DAML_ARCHITECTURE_PROPOSAL.md)

**If you're managing the project**: Read [IMPLEMENTATION_ROADMAP.md](./IMPLEMENTATION_ROADMAP.md)

---

**Questions?** Review the documentation above or reach out to the development team.