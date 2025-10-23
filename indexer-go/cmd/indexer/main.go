package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"canton-erc20/indexer-go/internal/httpserver"
	"canton-erc20/indexer-go/internal/ledgerclient"
	"canton-erc20/indexer-go/internal/state"
)

func main() {
	cfg := loadConfig()
	store := state.NewStore(cfg.TokenSymbol)

	httpSrv := httpserver.New(httpserver.Config{
		Port:        cfg.HTTPPort,
		TokenSymbol: cfg.TokenSymbol,
	}, store)
	httpSrv.Start()

	client, err := ledgerclient.New(ledgerclient.Config{
		Address:        cfg.LedgerAddress,
		LedgerID:       cfg.LedgerID,
		PackageID:      cfg.PackageID,
		IndexerParty:   cfg.IndexerParty,
		RequestTimeout: 30 * time.Second,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to create ledger client: %v\n", err)
		os.Exit(1)
	}
	defer client.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	offset, err := client.Bootstrap(ctx, store)
	if err != nil {
		fmt.Fprintf(os.Stderr, "bootstrap failed: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("[indexer-go] bootstrap complete, offset=%s\n", offset)

	go func() {
		if err := client.Stream(ctx, offset, store); err != nil {
			fmt.Fprintf(os.Stderr, "stream terminated: %v\n", err)
			cancel()
		}
	}()

	// Wait for shutdown signal
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	select {
	case <-sigCh:
		fmt.Println("[indexer-go] received shutdown signal")
	case <-ctx.Done():
		fmt.Println("[indexer-go] context cancelled")
	}
	cancel()
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer shutdownCancel()
	if err := httpSrv.Stop(shutdownCtx); err != nil {
		fmt.Fprintf(os.Stderr, "http shutdown error: %v\n", err)
	}
}

type config struct {
	LedgerAddress string
	LedgerID      string
	PackageID     string
	IndexerParty  string
	TokenSymbol   string
	HTTPPort      int
}

func loadConfig() config {
	cfg := config{
		LedgerAddress: env("LEDGER_ADDRESS", "127.0.0.1:6865"),
		LedgerID:      env("LEDGER_ID", "sandbox"),
		PackageID:     os.Getenv("ERC20_PKG_ID"),
		IndexerParty:  os.Getenv("INDEXER_PARTY"),
		TokenSymbol:   env("TOKEN_SYMBOL", "CCN"),
	HTTPPort:      envInt("PORT", 9000),
	}

	if cfg.PackageID == "" {
		fmt.Fprintln(os.Stderr, "ERC20_PKG_ID environment variable is required")
		os.Exit(1)
	}
	if cfg.IndexerParty == "" {
		fmt.Fprintln(os.Stderr, "INDEXER_PARTY environment variable is required")
		os.Exit(1)
	}
	return cfg
}

func env(key, fallback string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return fallback
}

func envInt(key string, fallback int) int {
	if val := os.Getenv(key); val != "" {
		if parsed, err := strconv.Atoi(val); err == nil {
			return parsed
		}
	}
	return fallback
}
