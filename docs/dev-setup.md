# Developer Environment Setup

This project targets macOS (Apple Silicon / Intel) and modern Linux distributions. The steps below install the tools required to run the Daml sandbox, JSON API, Node-based indexer, and middleware used in the vertical slice.

## Prerequisites

| Tool | Purpose | Minimum Version | Install Check |
| ---- | ------- | ----------------| --------------|
| Daml SDK | Ledger sandbox, JSON API, scripts | 2.10.x | `daml version` |
| Node.js & npm | Indexer & middleware services | Node 18+, npm 9+ | `node --version`, `npm --version` |
| OpenSSL | JWT helper scripts | system OpenSSL | `openssl version` |
| curl / jq | JSON API testing helpers | latest | `curl --version`, `jq --version` |

> ℹ️ Postgres is optional for the prototype. The Node indexer runs entirely in memory; switch to Postgres when hardening for production.

## macOS Installation (Homebrew)

```bash
# Install Homebrew if missing
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Daml SDK (installs to ~/.daml)
brew tap digitalasset/daml
brew install daml
daml install latest

# Node.js & npm (LTS)
brew install node@18

# Utilities
brew install jq
```

After installation, add the Daml CLI to your path if Homebrew does not do it automatically:

```bash
echo 'export PATH="$HOME/.daml/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

## Linux Installation (Debian / Ubuntu)

```bash
# Node.js & npm (NodeSource LTS repo)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs build-essential

# jq and curl (if missing)
sudo apt-get install -y jq curl

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

# Install Node dependencies for the indexer and middleware
(cd indexer && npm install)
(cd middleware && npm install)
```

## Optional: Postgres (for future persistence)

Install and start Postgres if you plan to persist the read model:

```bash
# macOS (Homebrew)
brew install postgresql@15
brew services start postgresql@15

# Ubuntu / Debian
sudo apt-get install postgresql postgresql-contrib
sudo systemctl start postgresql
```

Run the migration when you are ready to use Postgres instead of the in-memory indexer:

```bash
psql $DATABASE_URL -f indexer/migrations/001_create_token_tables.sql
```

## Validation

Confirm the tools are installed:

```bash
daml version
node --version
npm --version
```

Next steps: follow [startup-flow.md](./startup-flow.md) to launch the sandbox, JSON API, and services for the vertical slice.
