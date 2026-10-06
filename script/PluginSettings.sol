// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

/// @notice Version and metadata of the Multisig build that the deployment scripts publish.
/// @dev Per-build flow when preparing a new build:
///      1. Bump `VERSION_BUILD` (or `VERSION_RELEASE` for a new release).
///      2. Edit the JSON files under `script/metadata/`.
///      3. Pin each one with `just ipfs-pin <path>`.
///      4. Paste the returned `ipfs://<cid>` into the matching constant below.
///      The scripts refuse to run while a constant is empty (see `BaseScript._requireMetadata`).
library PluginSettings {
    uint8 internal constant VERSION_RELEASE = 1;
    uint8 internal constant VERSION_BUILD = 3;

    /// @dev Source: `script/metadata/build-metadata.json`.
    string internal constant BUILD_METADATA = "ipfs://QmRVs5yJzJ7rFPGRvVnzvimj63N7pWPzd169rud698AwsZ";
    /// @dev Source: `script/metadata/release-metadata.json`.
    string internal constant RELEASE_METADATA = "ipfs://QmRfQ7ghLZFy5DHQ63eDK3iPfXUP6igoupFYsy9whhYyJq";
    /// @dev Title, summary and description of the management DAO proposal that publishes the build.
    ///      Source: `script/metadata/new-version-proposal-metadata.json`.
    string internal constant PROPOSAL_METADATA = "ipfs://Qma3BneRJoRdHW3ptH19w3jLbENvFBDoSgW4qDCmFkjYt5";

    /// @dev Metadata of the placeholder builds that keep build numbers aligned across networks.
    ///      Same CID as the staged-proposal-processor-plugin uses for
    ///      `lib/osx/src/framework/plugin/repo/placeholder/placeholder-build-metadata.json`.
    string internal constant PLACEHOLDER_BUILD_METADATA = "ipfs://QmZDx8G5xuF9vqVbFGZ3KhF5nioL8gXwV3JbsEsSHvNMiz";
}
