package httpserver

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"canton-erc20/indexer-go/internal/state"
	"github.com/shopspring/decimal"
)

// Config for the HTTP server.
type Config struct {
	Port        int
	TokenSymbol string
}

// Server exposes REST endpoints backed by the in-memory state.
type Server struct {
	cfg   Config
	store *state.Store
	srv   *http.Server
}

// New creates a new HTTP server bound to the provided store.
func New(cfg Config, store *state.Store) *Server {
	mux := http.NewServeMux()
	s := &Server{
		cfg:   cfg,
		store: store,
		srv: &http.Server{
			Addr:              fmt.Sprintf(":%d", cfg.Port),
			Handler:           mux,
			ReadHeaderTimeout: 5 * time.Second,
		},
	}

	mux.HandleFunc("/healthz", s.handleHealthz)
	mux.HandleFunc("/balanceOf", s.handleBalanceOf)
	mux.HandleFunc("/allowance", s.handleAllowance)
	mux.HandleFunc("/totalSupply", s.handleTotalSupply)
	mux.HandleFunc("/state", s.handleState)

	return s
}

// Start begins serving HTTP requests in a background goroutine.
func (s *Server) Start() {
	go func() {
		if err := s.srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			fmt.Println("[http] server error:", err)
		}
	}()
	fmt.Printf("[http] listening on %s\n", s.srv.Addr)
}

// Stop gracefully shuts down the server.
func (s *Server) Stop(ctx context.Context) error {
	return s.srv.Shutdown(ctx)
}

func (s *Server) handleHealthz(w http.ResponseWriter, r *http.Request) {
	state.WriteJSON(w, http.StatusOK, map[string]any{
		"status":  "ok",
		"symbol":  s.cfg.TokenSymbol,
		"time":    time.Now().UTC().Format(time.RFC3339),
		"version": "go-indexer",
	})
}

func (s *Server) handleBalanceOf(w http.ResponseWriter, r *http.Request) {
	party := r.URL.Query().Get("party")
	if party == "" {
		http.Error(w, "`party` query parameter is required", http.StatusBadRequest)
		return
	}
	symbol := r.URL.Query().Get("symbol")
	balance := s.store.Balance(symbol, party)
	state.WriteJSON(w, http.StatusOK, map[string]any{
		"symbol":  chooseSymbol(symbol, s.cfg.TokenSymbol),
		"party":   party,
		"balance": balance.String(),
	})
}

func (s *Server) handleAllowance(w http.ResponseWriter, r *http.Request) {
	owner := r.URL.Query().Get("owner")
	spender := r.URL.Query().Get("spender")
	if owner == "" || spender == "" {
		http.Error(w, "`owner` and `spender` query parameters are required", http.StatusBadRequest)
		return
	}
	symbol := r.URL.Query().Get("symbol")
	value := s.store.AllowanceValue(symbol, owner, spender)
	state.WriteJSON(w, http.StatusOK, map[string]any{
		"symbol":  chooseSymbol(symbol, s.cfg.TokenSymbol),
		"owner":   owner,
		"spender": spender,
		"allowance": map[string]string{
			"value": value.String(),
		},
	})
}

func (s *Server) handleTotalSupply(w http.ResponseWriter, r *http.Request) {
	symbol := r.URL.Query().Get("symbol")
	total := s.store.TotalSupply(symbol)
	state.WriteJSON(w, http.StatusOK, map[string]any{
		"symbol": chooseSymbol(symbol, s.cfg.TokenSymbol),
		"total":  total.String(),
	})
}

func (s *Server) handleState(w http.ResponseWriter, r *http.Request) {
	state.WriteJSON(w, http.StatusOK, s.store.BuildSnapshot())
}

func chooseSymbol(symbol, fallback string) string {
	if symbol != "" {
		return symbol
	}
	return fallback
}

// ParseDecimal provides a helper for JSON responses where string -> decimal conversion may be needed.
func ParseDecimal(value string) (decimal.Decimal, error) {
	if value == "" {
		return decimal.Zero, nil
	}
	return decimal.NewFromString(value)
}

// ParseInt helper for query parameters.
func ParseInt(value string, fallback int) int {
	if value == "" {
		return fallback
	}
	if parsed, err := strconv.Atoi(value); err == nil {
		return parsed
	}
	return fallback
}
