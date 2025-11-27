# Canton Network Integration Guide

## Overview

Canton Network uses Daml smart contracts (not EVM/Solidity) and provides the Daml Ledger gRPC API for programmatic interaction. Since there is no official Go SDK, we integrate directly with the gRPC Ledger API.

## Architecture

### Canton Network Stack

```
┌──────────────────────────────────────┐
│       Canton Network                 │
│  ┌────────────────────────────────┐  │
│  │  Daml Smart Contracts          │  │
│  │  (Bridge Contract + CIP-56)    │  │
│  └────────────┬───────────────────┘  │
│               │                       │
│  ┌────────────▼───────────────────┐  │
│  │  Canton Participant Node       │  │
│  │  - Ledger State                │  │
│  │  - Privacy Layer               │  │
│  │  - Consensus                   │  │
│  └────────────┬───────────────────┘  │
│               │                       │
│  ┌────────────▼───────────────────┐  │
│  │  Daml Ledger gRPC API          │  │
│  │  - TransactionService          │  │
│  │  - CommandService              │  │
│  │  - ActiveContractsService      │  │
│  └────────────┬───────────────────┘  │
└───────────────┼───────────────────────┘
                │ gRPC + TLS + JWT
┌───────────────▼───────────────────────┐
│   Bridge Relayer (Go)                 │
│  ┌─────────────────────────────────┐  │
│  │  Canton Client                  │  │
│  │  - gRPC stubs (protobuf)        │  │
│  │  - Event streaming              │  │
│  │  - Command submission           │  │
│  │  - Offset management            │  │
│  └─────────────────────────────────┘  │
└───────────────────────────────────────┘
```

## Integration Approach

### 1. Use gRPC Ledger API Directly

**Why:**
- First-class, production-grade API
- Streaming with offsets for reliability
- Built-in deduplication
- No extra service dependencies (vs JSON API)
- Language-agnostic protocol buffers

**How:**
1. Generate Go client stubs from Daml Ledger API protobufs
2. Connect via gRPC with TLS
3. Authenticate with JWT tokens
4. Stream events and submit commands

### 2. Authentication & Authorization

**Canton uses JWT-based authorization (not client-side transaction signing)**

```go
// JWT claims required
{
  "actAs": ["BridgeOperatorParty"],  // Party that can submit commands
  "readAs": ["BridgeOperatorParty"],  // Party that can read events
  "exp": 1234567890
}
```

**Key Points:**
- No cryptographic transaction signing in client code
- Participant node handles internal signing
- JWT specifies which Canton party the client acts as
- Relayer must be configured as a party on the Canton Network

### 3. Monitoring Canton Events (Deposits)

**Event Streaming Pattern:**

```
1. GetLedgerEnd → get current offset
2. GetActiveContracts → snapshot of current state (optional)
3. GetTransactions → stream new events from offset
   └─> Filter by relayer party
   └─> Parse Created/Exercised events
   └─> Persist offset after processing
4. On reconnect → resume from last persisted offset
```

**Implementation:**
- Use `TransactionService.GetTransactions` with filter by relayer party
- Match events by template module/entity name (e.g., `BridgeModule:DepositEvent`)
- Persist offset in database after processing each batch
- Idempotent processing using transaction ID + event ID

### 4. Submitting Canton Transactions (Withdrawals)

**Command Submission Pattern:**

```
1. Build command (Create or Exercise)
2. Set actAs = bridge operator party
3. Set unique commandId (UUID)
4. Set applicationId for deduplication
5. Submit via CommandService.SubmitAndWait
6. Handle deduplication (ALREADY_EXISTS)
```

**Implementation:**
- Use `CommandService.SubmitAndWait` for synchronous submission
- Exercise choices on bridge contracts (e.g., `ReleaseFunds`, `MintWrapped`)
- Encode arguments as Daml Value (RecordValue, List, etc.)
- Implement retry logic with exponential backoff

### 5. Template Identifiers & Package IDs

**Challenge:** Daml packages have hash-based IDs that change on recompilation

**Solution:**
- Configure package IDs via environment variables/config
- Filter events by party, then match by module/entity name at runtime
- Avoid hardcoding package IDs in code
- Update config when Daml packages are redeployed

### 6. Daml Value Encoding/Decoding

Daml uses a specific value encoding in protobuf. We need helpers to convert:

```go
// Go struct → Daml Value
type DepositRequest struct {
    Amount    string  // Numeric as string
    Recipient string  // Party ID
    Token     string  // Contract ID
}

func (d *DepositRequest) ToDamlValue() *lapi.Value {
    return &lapi.Value{
        Sum: &lapi.Value_Record{
            Record: &lapi.Record{
                Fields: []*lapi.RecordField{
                    {Label: "amount", Value: numericValue(d.Amount)},
                    {Label: "recipient", Value: partyValue(d.Recipient)},
                    {Label: "token", Value: contractIdValue(d.Token)},
                },
            },
        },
    }
}
```

## Key Services from Ledger API

### TransactionService
- **GetTransactions**: Stream transactions with filter and offset
- **GetTransactionTrees**: Stream with full exercise trees (for nested workflows)
- **GetTransactionById**: Fetch specific transaction
- Used for: Monitoring deposit events

### CommandService
- **SubmitAndWait**: Submit command and wait for completion
- **SubmitAndWaitForTransaction**: Return full transaction
- **SubmitAndWaitForTransactionId**: Return only ID
- Used for: Submitting withdrawal/mint commands

### ActiveContractsService
- **GetActiveContracts**: Snapshot of all active contracts
- Used for: Initial state sync on startup

### LedgerIdentityService
- **GetLedgerIdentity**: Get ledger ID
- Used for: Validation and configuration

## Privacy Considerations

**Canton Network has privacy features:**
- Transaction details shared on need-to-know basis
- Relayer party must be stakeholder/observer on bridge contracts
- If not included in contract, relayer won't see events
- Coordinate with Daml contract developers to ensure visibility

**Template Design Requirements:**
- Bridge operator party must be signatory or observer on:
  - Deposit contracts (to monitor)
  - Bridge escrow contracts (to exercise release)
  - Token contracts (to mint/burn if applicable)

## Implementation Checklist

### Phase 1: Setup
- [ ] Pull Daml Ledger API protobuf definitions
- [ ] Generate Go stubs with protoc
- [ ] Configure TLS certificates
- [ ] Set up JWT authentication service
- [ ] Create Canton party for relayer

### Phase 2: Event Monitoring
- [ ] Implement GetTransactions streaming
- [ ] Parse Created/Exercised events
- [ ] Filter by bridge template identifiers
- [ ] Persist offsets in database
- [ ] Implement reconnect with resume from offset
- [ ] Add metrics for stream lag and events processed

### Phase 3: Command Submission
- [ ] Implement Daml Value encoding helpers
- [ ] Build ExerciseCommand for withdraw/release
- [ ] Implement SubmitAndWait with error handling
- [ ] Add deduplication tracking
- [ ] Implement retry logic
- [ ] Add metrics for command success/failure

### Phase 4: Reliability
- [ ] Idempotent event processing (event ID tracking)
- [ ] Transaction retry with exponential backoff
- [ ] Connection health monitoring
- [ ] JWT token refresh mechanism
- [ ] Handle Canton node reorgs/restart
- [ ] Implement graceful shutdown

## Configuration

```yaml
canton:
  rpc_url: "canton-participant-node:4001"  # gRPC endpoint
  ledger_id: "canton-network-mainnet"
  application_id: "canton-eth-bridge"
  tls:
    enabled: true
    cert_file: "/path/to/cert.pem"
    key_file: "/path/to/key.pem"
    ca_file: "/path/to/ca.pem"
  auth:
    jwt_issuer: "https://auth.canton.network"
    jwt_secret: "..."  # or use JWKS
  relayer_party: "BridgeOperatorParty::1234..."
  bridge_package_id: "abc123..."  # Set per deployment
  bridge_module: "BridgeModule"
  bridge_templates:
    deposit: "DepositRequest"
    escrow: "BridgeEscrow"
  dedup_duration: "30s"
  max_inbound_message_size: 104857600  # 100MB for large events
```

## Error Handling

### Common gRPC Errors

| Error | Cause | Handling |
|-------|-------|----------|
| `ALREADY_EXISTS` | Command deduplication hit | Log and skip (already processed) |
| `INVALID_ARGUMENT` | Malformed command | Log error, alert operator |
| `NOT_FOUND` | Contract ID doesn't exist | May be consumed, verify state |
| `PERMISSION_DENIED` | JWT missing or invalid party | Refresh token, check party config |
| `UNAVAILABLE` | Node down or network issue | Retry with backoff |
| `DEADLINE_EXCEEDED` | Timeout | Retry, check node health |

## Security Best Practices

1. **JWT Management**
   - Use short-lived tokens (1-24 hours)
   - Implement automatic refresh
   - Store secrets in vault/KMS
   - Minimal claims (only required parties)

2. **TLS Configuration**
   - Always use TLS in production
   - Validate server certificates
   - Use mTLS if available
   - Rotate certificates regularly

3. **Party Authorization**
   - Principle of least privilege
   - Separate parties for different operations
   - Audit party permissions
   - Monitor unauthorized access attempts

4. **Offset Persistence**
   - Persist offsets transactionally
   - Atomic DB writes with offset updates
   - Prevent event replay attacks
   - Regular offset backups

## Monitoring & Observability

### Key Metrics
- `canton_stream_lag_seconds` - Time behind ledger end
- `canton_events_processed_total` - Events processed counter
- `canton_commands_submitted_total` - Commands submitted (by status)
- `canton_grpc_errors_total` - gRPC errors by type
- `canton_offset_position` - Current stream offset
- `canton_jwt_refresh_total` - Token refresh events

### Logging
- Log all command submissions with commandId
- Log event processing with eventId and transactionId
- Log offset checkpoints
- Alert on stream disconnects
- Alert on repeated command failures

## Resources

- **Daml Documentation**: https://docs.digitalasset.com/
- **Ledger API Reference**: https://docs.digitalasset.com/build/3.3/reference/lapi-proto-docs.html
- **Canton Network Docs**: https://www.canton.network/developer-resources
- **Daml Protobufs**: https://github.com/digital-asset/daml (under ledger-api/grpc-definitions)
- **CIP-56 Token Standard**: https://www.canton.network/blog/what-is-cip-56-a-guide-to-cantons-token-standard

## Next Steps

1. Obtain Canton Network testnet access
2. Deploy Daml bridge contract to testnet
3. Generate Go protobufs for Ledger API
4. Implement Canton client with event streaming
5. Test end-to-end flow on testnet
6. Deploy to mainnet with monitoring
