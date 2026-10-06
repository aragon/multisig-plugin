import? 'lib/just-foundry/justfile'

default:
    @just help

DEPLOY_SCRIPT := "script/Deploy.s.sol:Deploy"
NEW_VERSION_SCRIPT := "script/NewVersion.s.sol:NewVersion"

# Fetch submodules, scaffold .env and select the network (default: mainnet)
[group('setup')]
init network="mainnet":
    #!/usr/bin/env bash
    set -euo pipefail
    git submodule update --init --recursive
    if [ ! -f .env ] && [ -f .env.example ]; then
        cp .env.example .env
        echo "Created .env from .env.example, edit it with your settings."
    fi
    if ! command -v forge &>/dev/null; then
        echo "Error: Foundry is not installed. Run 'just setup' to install it."
        exit 1
    fi
    just switch {{ network }}

# Dry-run the new-version script (no broadcast), review the printed proposal calldata
[group('upgrade')]
pre-new-version:
    just dry-run {{ NEW_VERSION_SCRIPT }}

# Publish a new plugin version (deploys the setup, prints the management DAO proposal calldata)
[group('upgrade')]
new-version:
    just run {{ NEW_VERSION_SCRIPT }}
