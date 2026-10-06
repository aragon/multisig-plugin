// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

import {MultisigSetup} from "../src/MultisigSetup.sol";
import {PluginSettings} from "./PluginSettings.sol";

contract BaseScript is Script {
    error InvalidVersionBuild(uint8 build, uint256 latestBuild);
    error MetadataNotPinned(string name);

    /// @dev Slug and canonical ENS name that artifacts-hub reserves for this plugin.
    ///      Must match the entry in aragon/artifacts-hub `scripts/lib/plugin-catalog.ts`.
    string internal constant PLUGIN_SLUG = "multisig";
    string internal constant PLUGIN_ENS = "multisig.plugin.dao.eth";

    MultisigSetup public multisigSetup;
    PluginRepo public multisigRepo;

    uint256 internal deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
    address internal deployer = vm.addr(deployerPrivateKey);

    /// @dev Publishing with an empty URI would make the build unusable by UIs, and the URI can
    ///      never be changed for that build afterwards. Fail before broadcasting anything.
    function _requireMetadata() internal pure {
        if (bytes(PluginSettings.BUILD_METADATA).length == 0) revert MetadataNotPinned("BUILD_METADATA");
        if (bytes(PluginSettings.RELEASE_METADATA).length == 0) revert MetadataNotPinned("RELEASE_METADATA");
        if (bytes(PluginSettings.PROPOSAL_METADATA).length == 0) revert MetadataNotPinned("PROPOSAL_METADATA");
    }

    function _versionString(uint8 _release, uint8 _build) internal pure returns (string memory) {
        return string.concat("v", vm.toString(_release), ".", vm.toString(_build));
    }

    /// @notice Writes a single-version `PluginArtifact` envelope to
    ///         `artifacts/artifacts-<NETWORK_NAME>-<block.timestamp>.json`, in the shape defined by
    ///         `PluginArtifact` in aragon/artifacts-hub `scripts/schema.ts`.
    ///         `just import-plugin <path>` in artifacts-hub merges it under `plugins.multisig`.
    /// @dev Skipped in simulations. Placeholder builds are not recorded; `just ingest` in
    ///      artifacts-hub enumerates the full on-chain version list.
    function _writeArtifact(address _maintainer, address _setup, address _implementation) internal {
        if (vm.envOr("SIMULATION", false)) return;

        string memory networkName = vm.envString("NETWORK_NAME");
        string memory timestamp = vm.toString(block.timestamp);

        string memory header = string.concat(
            "{\n",
            "  \"chainId\": ",
            vm.toString(block.chainid),
            ",\n",
            "  \"network\": \"",
            networkName,
            "\",\n",
            "  \"timestamp\": ",
            timestamp,
            ",\n",
            "  \"slug\": \"",
            PLUGIN_SLUG,
            "\",\n"
        );
        string memory plugin = string.concat(
            "  \"plugin\": {\n",
            "    \"repo\": \"",
            vm.toString(address(multisigRepo)),
            "\",\n",
            "    \"ens\": \"",
            PLUGIN_ENS,
            "\",\n",
            "    \"maintainer\": \"",
            vm.toString(_maintainer),
            "\",\n"
        );
        string memory versions = string.concat(
            "    \"versions\": [\n",
            "      {\n",
            "        \"release\": ",
            vm.toString(uint256(PluginSettings.VERSION_RELEASE)),
            ",\n",
            "        \"build\": ",
            vm.toString(uint256(PluginSettings.VERSION_BUILD)),
            ",\n",
            "        \"setup\": \"",
            vm.toString(_setup),
            "\",\n",
            "        \"implementation\": \"",
            vm.toString(_implementation),
            "\",\n",
            "        \"current\": true\n",
            "      }\n",
            "    ]\n",
            "  }\n",
            "}\n"
        );

        string memory dir = string.concat(vm.projectRoot(), "/artifacts");
        vm.createDir(dir, true);
        vm.writeFile(
            string.concat(dir, "/artifacts-", networkName, "-", timestamp, ".json"),
            string.concat(header, plugin, versions)
        );
    }
}
