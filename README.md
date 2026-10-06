# Multisig Plugin [![Foundry][foundry-badge]][foundry] [![License: AGPL v3][license-badge]][license]

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
[license]: https://opensource.org/licenses/AGPL-v3
[license-badge]: https://img.shields.io/badge/License-AGPL_v3-blue.svg

An Aragon OSx governance plugin where a proposal passes once X out of Y listed members approve it on-chain.

Documentation: [protocol-doc, Multisig Plugin](https://github.com/aragon/protocol-doc/blob/main/plugins/multisig-plugin.md).

## Audit

### v1.3.0

**Halborn**: [audit report](https://github.com/aragon/osx/tree/main/audits/Halborn_AragonOSx_v1_4_Smart_Contract_Security_Assessment_Report_2025_01_03.pdf)

- Commit ID: [fffc680f563698cfb7aec962fb89b4196025f629](https://github.com/aragon/multisig-plugin/commit/fffc680f563698cfb7aec962fb89b4196025f629)
- Started: 2024-11-18
- Finished: 2025-02-13

## Contracts

| Contract | Purpose |
|---|---|
| `src/Multisig.sol` | The plugin (UUPS upgradeable). |
| `src/MultisigSetup.sol` | Plugin setup: installs, updates and uninstalls the plugin through the `PluginSetupProcessor`. |
| `src/ListedCheckCondition.sol` | Permission condition enforcing `onlyListed` on proposal creation. |
| `src/IMultisig.sol` | Interface. |

Deployed addresses and ABIs are published in [artifacts-hub](https://github.com/aragon/artifacts-hub).

## Setup

Requirements: [Foundry](https://getfoundry.sh/) and [just](https://github.com/casey/just).

```shell
git clone https://github.com/aragon/multisig-plugin.git
cd multisig-plugin
just init <network>   # fetch the git submodules (lib/), create .env from .env.example, select the network (default: mainnet)
just help             # list every recipe (available once the submodules are fetched)
```

Network settings (RPC, chain ID, OSx and management DAO addresses) come from [just-foundry](https://github.com/aragon/just-foundry) (`lib/just-foundry/networks/<network>.env`). Switch networks with `just switch <network>` and inspect the resolved values with `just env`. Secrets go in `.env` (see `.env.example`) or in `vars` (see `.vars.yaml`).

## Build

```shell
forge build
```

## Test

```shell
just test            # unit, integration, fuzz and invariant tests
just test-fork       # fork tests against the active network (requires RPC_URL)
just test-coverage   # HTML coverage report under ./report
```

Layout:

```
test/
├── unit/<contract>/concrete/<function>/    one folder per function
├── unit/<contract>/fuzz/
├── unit/metadata/                          build metadata vs what the contracts decode
├── unit/script/                            deployment scripts
├── integration/concrete/pluginSetup/       install, update and uninstall through a local PluginSetupProcessor
├── integration/fuzz/                       invariants
├── fork/                                   live networks
└── utils/                                  constants, mocks, harnesses
```

## Deploy

```shell
just predeploy       # simulate Deploy.s.sol
just deploy          # new network: creates the plugin repo and publishes VERSION_BUILD
just pre-new-version # simulate NewVersion.s.sol
just new-version     # existing repo: deploys the setup, prints the management DAO proposal
```

- `Deploy.s.sol` creates the plugin repo (ENS subdomain `MULTISIG_ENS_SUBDOMAIN`, set it to `multisig` in production; a unique `multisig-<timestamp>` otherwise), publishes `PlaceholderSetup` builds below `VERSION_BUILD` so that build numbers match every other network, publishes `MultisigSetup` as `VERSION_BUILD`, and hands ROOT, MAINTAINER and UPGRADE_REPO over to the management DAO.
- `NewVersion.s.sol` deploys `MultisigSetup` and prints the `createVersion` action(s) for `MULTISIG_PLUGIN_REPO_ADDRESS`, wrapped in a `createProposal` call for `MANAGEMENT_DAO_MULTISIG_ADDRESS`. Any member of the management DAO multisig submits it.

Both scripts write `artifacts/artifacts-<network>-<timestamp>.json` for artifacts-hub (`just import-plugin <file>` there). For `NewVersion`, import it only after the proposal has executed.

### Preparing a new build

1. Bump `VERSION_BUILD` in `script/PluginSettings.sol` (and `VERSION_RELEASE` for a new release).
2. Update the files in `script/metadata/`: `build-metadata.json` (its `prepareUpdate` keys are the builds that can update *from*), `new-version-proposal-metadata.json`, and `release-metadata.json` on a new release.
3. Pin each file with `just ipfs-pin <file>` and paste the `ipfs://` URIs into `script/PluginSettings.sol`. The scripts refuse to run while any of them is empty.

### Updating existing installations

Publishing a build does not update installed plugins: each DAO applies the update through the `PluginSetupProcessor`. Since build 3, `MultisigSetup` does not grant `UPGRADE_PLUGIN_PERMISSION` to the DAO and `prepareUpdate` from build 3 returns no permissions. A DAO updating from build 3 to a build with a new implementation must therefore grant `UPGRADE_PLUGIN_PERMISSION` on the plugin to the `PluginSetupProcessor`, apply the update and revoke it, in the same proposal.

### Deployment checklist

- [ ] I have checked out the official repository on the `main` branch, and `git status` reports no local changes
- [ ] The rest of the ceremony reports the same `git log -n 1` commit hash
- [ ] I have run `just init <network>` and `just env` shows the right network, addresses and deployer
- [ ] `DEPLOYER_KEY` is a fresh wallet that only I operate
- [ ] `ETHERSCAN_API_KEY` is set (when the network uses Etherscan)
- [ ] `VERSION_BUILD` and every metadata URI in `script/PluginSettings.sol` are final
- [ ] `MULTISIG_ENS_SUBDOMAIN=multisig` (new network only)
- [ ] `just test` runs clean, and `just test-fork` runs clean on the target network
- [ ] `just predeploy` (or `just pre-new-version`) completes without errors
- [ ] `just balance` shows at least 15% more funds than the simulation estimated
- [ ] My machine is on a trusted network and exposes no services
- [ ] I run `just deploy` (or `just new-version`)

### Post deployment checklist

- [ ] The script completed without errors and every contract is verified on the network's explorer
- [ ] The log under `logs/` matches the console output
- [ ] `artifacts/artifacts-<network>-<timestamp>.json` matches the logged addresses, and it was imported into artifacts-hub (after the proposal executed, for `NewVersion`)
- [ ] The plugin repo's ROOT, MAINTAINER and UPGRADE_REPO permissions belong to the management DAO only (`Deploy`)
- [ ] The log, the artifact and `broadcast/<script>/<chain-id>/run-latest.json` are uploaded to the shared location

## zkSync

just-foundry selects `forge-zksync` automatically on zkSync networks (`just switch zksync` or `zksync-sepolia`). `MultisigSetup` deploys plugins as UUPS proxies and conditions with `new`, so no zkSync-specific setup is needed.

## License

AGPL-3.0-or-later, see [LICENSE.md](./LICENSE.md).
