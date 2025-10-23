# Developer Environment Setup

This project targets macOS (Apple Silicon / Intel) and modern Linux distributions. The steps below install the tools required to run the Daml sandbox, Go-based indexer (Ledger gRPC), and Node.js middleware used in the vertical slice.

## Prerequisites

| Tool | Purpose | Minimum Version | Install Check |
| ---- | ------- | ----------------| --------------|
| Daml SDK | Ledger sandbox & scripts | 2.10.x | `daml version` |
| Go | Ledger gRPC indexer | 1.21+ | `go version` |
| Node.js & npm | Middleware service | Node 18+, npm 9+ | `node --version`, `npm --version` |
| protoc | gRPC code generation | 3.21+ | `protoc --version` |

> ℹ️ Postgres is optional for the prototype. The Go indexer runs entirely in memory; introduce Postgres when hardening for production.

## macOS Installation (Homebrew)

```bash
# Install Homebrew if missing
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Daml SDK (installs to ~/.daml)
brew tap digitalasset/daml
brew install daml
daml install latest

# Go (optional, via Homebrew)
brew install go

# Node.js & npm (middleware)
brew install node@18
```

After installation, add the Daml CLI to your path if Homebrew does not do it automatically:

```bash
echo 'export PATH="$HOME/.daml/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

## Linux Installation (Debian / Ubuntu)

```bash
# Go
sudo apt-get install -y golang

# Node.js & npm (NodeSource LTS repo)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs build-essential

# Daml SDK installer
curl -sSL https://get.daml.com/ | sh
echo 'export PATH="$HOME/.daml/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

daml install latest
```

For other distributions, follow the instructions at [https://docs.daml.com/getting-started/installation.html](https://docs.daml.com/getting-started/installation.html).

## Repository Setup

```bash
git clone https://github.com/<your-org>/canton-ERC20.git
cd canton-ERC20

# Install middleware dependencies
(cd middleware && npm install)

# (Optional, run once with network) generate Go ledger stubs and fetch deps
cd indexer-go
./scripts/gen-ledger.sh
go mod tidy
cd ..
```

## Validation

Confirm the tools are installed:

```bash
daml version
go version
protoc --version
node --version
npm --version
```

Next steps: follow [startup-flow.md](./startup-flow.md) to launch the sandbox, Go indexer, and middleware for the vertical slice.
