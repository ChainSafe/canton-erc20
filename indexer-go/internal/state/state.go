package state

import (
	"encoding/json"
	"net/http"
	"sort"
	"sync"

	"github.com/shopspring/decimal"
)

// TokenMeta captures the metadata stored on-chain.
type TokenMeta struct {
	Name     string `json:"name"`
	Symbol   string `json:"symbol"`
	Decimals int32  `json:"decimals"`
}

// Holding represents an active TokenHolding contract.
type Holding struct {
	ContractID string          `json:"contractId"`
	Issuer     string          `json:"issuer"`
	Owner      string          `json:"owner"`
	Amount     decimal.Decimal `json:"amount"`
	Meta       TokenMeta       `json:"meta"`
}

// Allowance represents an active Allowance contract.
type Allowance struct {
	ContractID string          `json:"contractId"`
	Issuer     string          `json:"issuer"`
	Owner      string          `json:"owner"`
	Spender    string          `json:"spender"`
	Limit      decimal.Decimal `json:"limit"`
	Meta       TokenMeta       `json:"meta"`
}

// Store keeps the indexer's in-memory projection.
type Store struct {
	mu          sync.RWMutex
	holdings    map[string]Holding   // contractID -> holding
	allowances  map[string]Allowance // contractID -> allowance
	tokenSymbol string
}

// Sink defines the methods consumed by the ledger client when applying updates.
type Sink interface {
	UpsertHolding(Holding)
	RemoveHolding(contractID string)
	UpsertAllowance(Allowance)
	RemoveAllowance(contractID string)
}

// NewStore constructs an empty store.
func NewStore(tokenSymbol string) *Store {
	return &Store{
		holdings:    make(map[string]Holding),
		allowances:  make(map[string]Allowance),
		tokenSymbol: tokenSymbol,
	}
}

// UpsertHolding adds or updates a holding contract.
func (s *Store) UpsertHolding(h Holding) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.holdings[h.ContractID] = h
}

// RemoveHolding archives a holding contract.
func (s *Store) RemoveHolding(contractID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.holdings, contractID)
}

// UpsertAllowance adds or updates an allowance contract.
func (s *Store) UpsertAllowance(a Allowance) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.allowances[a.ContractID] = a
}

// RemoveAllowance archives an allowance contract.
func (s *Store) RemoveAllowance(contractID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.allowances, contractID)
}

// Balance returns the aggregate balance for a party.
func (s *Store) Balance(symbol, party string) decimal.Decimal {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if symbol == "" {
		symbol = s.tokenSymbol
	}
	total := decimal.Zero
	for _, h := range s.holdings {
		if h.Meta.Symbol == symbol && h.Owner == party {
			total = total.Add(h.Amount)
		}
	}
	return total
}

// AllowanceValue returns the allowance from owner to spender.
func (s *Store) AllowanceValue(symbol, owner, spender string) decimal.Decimal {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if symbol == "" {
		symbol = s.tokenSymbol
	}
	for _, a := range s.allowances {
		if a.Meta.Symbol == symbol && a.Owner == owner && a.Spender == spender {
			return a.Limit
		}
	}
	return decimal.Zero
}

// TotalSupply returns the total supply for a symbol.
func (s *Store) TotalSupply(symbol string) decimal.Decimal {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if symbol == "" {
		symbol = s.tokenSymbol
	}
	total := decimal.Zero
	for _, h := range s.holdings {
		if h.Meta.Symbol == symbol {
			total = total.Add(h.Amount)
		}
	}
	return total
}

// Snapshot is returned from the debug /state endpoint.
type Snapshot struct {
	TokenSymbol     string            `json:"tokenSymbol"`
	Holdings        []Holding         `json:"holdings"`
	Allowances      []Allowance       `json:"allowances"`
	TotalSupply     string            `json:"totalSupply"`
	BalancesByParty map[string]string `json:"balances"`
}

// BuildSnapshot builds a snapshot of the current state.
func (s *Store) BuildSnapshot() Snapshot {
	s.mu.RLock()
	defer s.mu.RUnlock()

	holdings := make([]Holding, 0, len(s.holdings))
	for _, h := range s.holdings {
		holdings = append(holdings, h)
	}
	sort.Slice(holdings, func(i, j int) bool { return holdings[i].ContractID < holdings[j].ContractID })

	allowances := make([]Allowance, 0, len(s.allowances))
	for _, a := range s.allowances {
		allowances = append(allowances, a)
	}
	sort.Slice(allowances, func(i, j int) bool { return allowances[i].ContractID < allowances[j].ContractID })

	balances := map[string]decimal.Decimal{}
	total := decimal.Zero
	for _, h := range holdings {
		total = total.Add(h.Amount)
		bal := balances[h.Owner]
		balances[h.Owner] = bal.Add(h.Amount)
	}

	prettyBalances := map[string]string{}
	for party, bal := range balances {
		prettyBalances[party] = bal.String()
	}

	return Snapshot{
		TokenSymbol:     s.tokenSymbol,
		Holdings:        holdings,
		Allowances:      allowances,
		TotalSupply:     total.String(),
		BalancesByParty: prettyBalances,
	}
}

// WriteJSON writes an arbitrary payload as JSON response.
func WriteJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	_ = enc.Encode(payload)
}
