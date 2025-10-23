package ledgerclient

import (
	"context"
	"errors"
	"fmt"
	"io"
	"time"

	apiv1 "canton-erc20/indexer-go/gen/com/daml/ledger/api/v1"
	"canton-erc20/indexer-go/internal/state"
	"github.com/shopspring/decimal"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

const (
	tokenHoldingModule = "ERC20.Token"
	tokenHoldingName   = "TokenHolding"

	allowanceModule = "ERC20.Allowance"
	allowanceName   = "Allowance"
)

// Config encapsulates client configuration.
type Config struct {
	Address        string
	LedgerID       string
	PackageID      string
	IndexerParty   string
	RequestTimeout time.Duration
}

// Client consumes the ledger gRPC API and pushes updates into the store.
type Client struct {
	cfg     Config
	conn    *grpc.ClientConn
	acs     apiv1.ActiveContractsServiceClient
	txsvc   apiv1.TransactionServiceClient
	filters *apiv1.TransactionFilter
}

// New creates a ledger client using plaintext connection (suitable for dev).
func New(cfg Config) (*Client, error) {
	if cfg.Address == "" {
		cfg.Address = "127.0.0.1:6865"
	}
	if cfg.LedgerID == "" {
		cfg.LedgerID = "sandbox"
	}
	if cfg.IndexerParty == "" {
		return nil, errors.New("IndexerParty is required")
	}
	if cfg.PackageID == "" {
		return nil, errors.New("PackageID is required")
	}
	if cfg.RequestTimeout == 0 {
		cfg.RequestTimeout = 10 * time.Second
	}

	conn, err := grpc.Dial(cfg.Address, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return nil, fmt.Errorf("dial ledger: %w", err)
	}

 filter := &apiv1.TransactionFilter{
 	FiltersByParty: map[string]*apiv1.Filters{
 		cfg.IndexerParty: {
 			Inclusive: &apiv1.InclusiveFilters{
 				TemplateFilters: []*apiv1.TemplateFilter{
 					{
 						TemplateId: &apiv1.Identifier{
 							PackageId:  cfg.PackageID,
 							ModuleName: tokenHoldingModule,
 							EntityName: tokenHoldingName,
 						},
 					},
 					{
 						TemplateId: &apiv1.Identifier{
 							PackageId:  cfg.PackageID,
 							ModuleName: allowanceModule,
 							EntityName: allowanceName,
 						},
 					},
 				},
 			},
 		},
 	},
 }

	return &Client{
		cfg:     cfg,
		conn:    conn,
		acs:     apiv1.NewActiveContractsServiceClient(conn),
		txsvc:   apiv1.NewTransactionServiceClient(conn),
		filters: filter,
	}, nil
}

// Close terminates the underlying gRPC connection.
func (c *Client) Close() error {
	return c.conn.Close()
}

// Bootstrap loads the initial snapshot into the provided sink and returns the offset.
func (c *Client) Bootstrap(ctx context.Context, sink state.Sink) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, c.cfg.RequestTimeout)
	defer cancel()

	stream, err := c.acs.GetActiveContracts(ctx, &apiv1.GetActiveContractsRequest{
		LedgerId:       c.cfg.LedgerID,
		Filter:         c.filters,
		Verbose:        true,
		ActiveAtOffset: "",
	})
	if err != nil {
		return "", fmt.Errorf("GetActiveContracts: %w", err)
	}

	var snapshotOffset string
	for {
		resp, err := stream.Recv()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return "", fmt.Errorf("active stream recv: %w", err)
		}
		for _, evt := range resp.GetActiveContracts() {
			if err := c.handleCreated(evt, sink); err != nil {
				return "", err
			}
		}
		if resp.GetOffset() != "" {
			snapshotOffset = resp.GetOffset()
		}
	}
	if snapshotOffset == "" {
		// Fallback to ledger begin.
		snapshotOffset = "0"
	}
	return snapshotOffset, nil
}

// Stream consumes the Ledger API transaction stream from the provided offset (exclusive).
func (c *Client) Stream(ctx context.Context, offset string, sink state.Sink) error {
 begin := &apiv1.LedgerOffset{}
 if offset == "" {
 	begin.Value = &apiv1.LedgerOffset_Boundary{Boundary: apiv1.LedgerOffset_LEDGER_BEGIN}
 } else {
 	begin.Value = &apiv1.LedgerOffset_Absolute{Absolute: offset}
 }

	req := &apiv1.GetTransactionsRequest{
		LedgerId: c.cfg.LedgerID,
		Begin:    begin,
		Filter:   c.filters,
		Verbose:  true,
	}

	stream, err := c.txsvc.GetTransactions(ctx, req)
	if err != nil {
		return fmt.Errorf("GetTransactions: %w", err)
	}

	for {
		resp, err := stream.Recv()
		if errors.Is(err, io.EOF) || errors.Is(err, context.Canceled) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("transaction stream: %w", err)
		}
		for _, tx := range resp.GetTransactions() {
			for _, event := range tx.GetEvents() {
				switch ev := event.Event.(type) {
				case *apiv1.Event_Created:
					if err := c.handleCreated(ev.Created, sink); err != nil {
						return err
					}
				case *apiv1.Event_Archived:
					if err := c.handleArchived(ev.Archived, sink); err != nil {
						return err
					}
				}
			}
		}
	}
}

func (c *Client) handleCreated(evt *apiv1.CreatedEvent, sink state.Sink) error {
	template := evt.GetTemplateId()
	switch template.GetModuleName() {
	case tokenHoldingModule:
		if template.GetEntityName() != tokenHoldingName {
			return nil
		}
		holding, err := parseHolding(evt)
		if err != nil {
			return fmt.Errorf("parse holding: %w", err)
		}
		sink.UpsertHolding(holding)
	case allowanceModule:
		if template.GetEntityName() != allowanceName {
			return nil
		}
		allowance, err := parseAllowance(evt)
		if err != nil {
			return fmt.Errorf("parse allowance: %w", err)
		}
		sink.UpsertAllowance(allowance)
	default:
		// ignore other templates
	}
	return nil
}

func (c *Client) handleArchived(evt *apiv1.ArchivedEvent, sink state.Sink) error {
	template := evt.GetTemplateId()
	switch template.GetModuleName() {
	case tokenHoldingModule:
		sink.RemoveHolding(evt.GetContractId())
	case allowanceModule:
		sink.RemoveAllowance(evt.GetContractId())
	default:
	}
	return nil
}

func parseHolding(evt *apiv1.CreatedEvent) (state.Holding, error) {
	args := evt.GetCreateArguments()
	if args == nil {
		return state.Holding{}, errors.New("missing create arguments")
	}
	fields := recordToMap(args)
	issuer := valueToParty(fields["issuer"])
	owner := valueToParty(fields["owner"])
	amount, err := valueToDecimal(fields["amount"])
	if err != nil {
		return state.Holding{}, err
	}
	meta, err := valueToMeta(fields["meta"])
	if err != nil {
		return state.Holding{}, err
	}
	return state.Holding{
		ContractID: evt.GetContractId(),
		Issuer:     issuer,
		Owner:      owner,
		Amount:     amount,
		Meta:       meta,
	}, nil
}

func parseAllowance(evt *apiv1.CreatedEvent) (state.Allowance, error) {
	args := evt.GetCreateArguments()
	if args == nil {
		return state.Allowance{}, errors.New("missing create arguments")
	}
	fields := recordToMap(args)
	issuer := valueToParty(fields["issuer"])
	owner := valueToParty(fields["owner"])
	spender := valueToParty(fields["spender"])
	limit, err := valueToDecimal(fields["limit"])
	if err != nil {
		return state.Allowance{}, err
	}
	meta, err := valueToMeta(fields["meta"])
	if err != nil {
		return state.Allowance{}, err
	}
	return state.Allowance{
		ContractID: evt.GetContractId(),
		Issuer:     issuer,
		Owner:      owner,
		Spender:    spender,
		Limit:      limit,
		Meta:       meta,
	}, nil
}

func recordToMap(rec *apiv1.Record) map[string]*apiv1.Value {
	result := make(map[string]*apiv1.Value, len(rec.GetFields()))
	for _, field := range rec.GetFields() {
		result[field.GetLabel()] = field.GetValue()
	}
	return result
}

func valueToParty(v *apiv1.Value) string {
	if v == nil {
		return ""
	}
	return v.GetParty()
}

func valueToText(v *apiv1.Value) string {
	if v == nil {
		return ""
	}
	return v.GetText()
}

func valueToInt32(v *apiv1.Value) (int32, error) {
	if v == nil {
		return 0, errors.New("nil int value")
	}
	return int32(v.GetInt64()), nil
}

func valueToDecimal(v *apiv1.Value) (decimal.Decimal, error) {
	if v == nil {
		return decimal.Decimal{}, errors.New("nil decimal value")
	}
	if n := v.GetNumeric(); n != "" {
		return decimal.NewFromString(n)
	}
	if txt := v.GetText(); txt != "" {
		return decimal.NewFromString(txt)
	}
	return decimal.Decimal{}, errors.New("unsupported decimal encoding")
}

func valueToMeta(v *apiv1.Value) (state.TokenMeta, error) {
	rec := v.GetRecord()
	if rec == nil {
		return state.TokenMeta{}, errors.New("meta is not record")
	}
	fields := recordToMap(rec)
	name := valueToText(fields["name"])
	symbol := valueToText(fields["symbol"])
	decimals, err := valueToInt32(fields["decimals"])
	if err != nil {
		return state.TokenMeta{}, err
	}
	return state.TokenMeta{
		Name:     name,
		Symbol:   symbol,
		Decimals: decimals,
	}, nil
}
