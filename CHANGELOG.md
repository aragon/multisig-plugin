# Multisig Plugin

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to the [Aragon OSx Plugin Versioning Convention](https://devs.aragon.org/docs/osx/how-to-guides/plugin-development/publication/versioning).

## Unreleased

### Changed

- `Multisig`: functions are `virtual` and several `external` functions are `public`, so that the plugin can be extended (not covered by the v1.3 audit).
- Migrated the project from Hardhat to Foundry: sources in `src/`, tests rewritten in Solidity, deployment scripts in `script/` driven by `just` and `just-foundry`.
- OSx and osx-commons come from the `lib/osx` submodule.

### Fixed

- `build-metadata.json`: the `prepareUpdate` inputs were declared under the wrong source builds. Updating from builds 1 and 2 requires `(targetConfig, metadata)`.

### Removed

- The `@aragon/multisig-plugin-artifacts` npm package. ABIs and addresses are published in artifacts-hub.

## v1.3

### Added

- Copied files from [aragon/osx commit 1130df](https://github.com/aragon/osx/commit/1130dfce94fd294c4341e91a8f3faccc54cf43b7)
- `createProposal` standardized function.
- `createProposal` function is auth protected.
- `ListedCheckCondition` permission condition to grant the create proposal permission. This condition will allow the creation based on plugin's setup.
- `execute` function is auth protected, when the plugin is installed this permission will be granted to `ANY_ADDRESS`.
- The plugin inherits now from `MetadataExtensionUpgradeable`, meaning that the plugin has metadata that can be get/set (`getMetadata`, `setMetadata`).
- `initialize` function receives also `pluginMetadata` and `TargetConfig`.
- `hasSucceeded` and `customProposalParamsABI` function implementing to `IProposal` interface.

### Changed

- Bumped OpenZepplin to `4.9.6`.
- Used `ProxyLib` from `osx-commons-contracts` for the UUPS proxy deployment in `MultisigSetup`.
- Hard-coded the `bytes32 internal constant EXECUTE_PERMISSION_ID` constant in `MultisigSetup` until it is available in `PermissionLib`.
- Changed the `prepareInstallation` function in `MultisigSetup` to not unnecessarily grant the `UPGRADE_PLUGIN_PERMISSION_ID` permission to the installing DAO.
- Changed the `prepareUpdate` function in `MultisigSetup` to revoke the previously unnecessarily granted `UPGRADE_PLUGIN_PERMISSION_ID` permission from the installing DAO.
