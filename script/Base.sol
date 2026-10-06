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

    /// @notice One published build, as recorded in the artifact.
    /// @param placeholder The build uses an OSx `PlaceholderSetup` (no plugin, never installable).
    struct ArtifactVersion {
        uint16 build;
        address setup;
        address implementation;
        bool placeholder;
    }

    /// @notice Writes a `PluginArtifact` envelope to `artifacts/artifacts-<NETWORK_NAME>-<block.timestamp>.json`,
    ///         in the shape defined by `PluginArtifact` in aragon/artifacts-hub `scripts/schema.ts`.
    ///         `just import-plugin <path>` in artifacts-hub merges it under `plugins.multisig`.
    /// @dev Skipped in simulations. Records every build the run published: placeholders carry
    ///      `placeholder: true` and no implementation; the last version is marked `current`
    ///      (artifacts-hub derives `current` again on import).
    function _writeArtifact(address _maintainer, ArtifactVersion[] memory _versions) internal {
        if (vm.envOr("SIMULATION", false)) return;

        string memory networkName = vm.envString("NETWORK_NAME");
        string memory timestamp = vm.toString(block.timestamp);

        string memory versions;
        for (uint256 i; i < _versions.length; ++i) {
            versions =
                string.concat(versions, i == 0 ? "" : ",\n", _versionJson(_versions[i], i == _versions.length - 1));
        }

        string memory json = string.concat(
            "{\n",
            "  \"chainId\": ",
            vm.toString(block.chainid),
            ",\n  \"network\": \"",
            networkName,
            "\",\n  \"timestamp\": ",
            timestamp,
            ",\n  \"slug\": \"",
            PLUGIN_SLUG,
            "\",\n  \"plugin\": {\n    \"repo\": \"",
            vm.toString(address(multisigRepo)),
            "\",\n    \"ens\": \"",
            PLUGIN_ENS,
            "\",\n    \"maintainer\": \"",
            vm.toString(_maintainer),
            "\",\n    \"versions\": [\n",
            versions,
            "\n    ]\n  }\n}\n"
        );

        string memory dir = string.concat(vm.projectRoot(), "/artifacts");
        vm.createDir(dir, true);
        vm.writeFile(string.concat(dir, "/artifacts-", networkName, "-", timestamp, ".json"), json);
    }

    function _versionJson(ArtifactVersion memory _version, bool _current) private pure returns (string memory) {
        string memory tail = _version.placeholder
            ? "        \"placeholder\": true\n"
            : string.concat(
                "        \"implementation\": \"",
                vm.toString(_version.implementation),
                "\",\n        \"current\": ",
                _current ? "true" : "false",
                "\n"
            );
        return string.concat(
            "      {\n        \"release\": ",
            vm.toString(uint256(PluginSettings.VERSION_RELEASE)),
            ",\n        \"build\": ",
            vm.toString(uint256(_version.build)),
            ",\n        \"setup\": \"",
            vm.toString(_version.setup),
            "\",\n",
            tail,
            "      }"
        );
    }
}
