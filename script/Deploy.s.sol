// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PlaceholderSetup} from "@aragon/osx/framework/plugin/repo/placeholder/PlaceholderSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";

import {MultisigSetup} from "../src/MultisigSetup.sol";
import {ListedCheckCondition} from "../src/ListedCheckCondition.sol";
import {BaseScript} from "./Base.sol";
import {PluginSettings} from "./PluginSettings.sol";

/// @notice Deploys the Multisig plugin on a network from scratch: a new plugin repo (with ENS
///         subdomain), placeholder builds up to `VERSION_BUILD - 1`, the setup published as
///         `VERSION_BUILD`, and the repo handed over to the management DAO.
/// @dev For networks where the repo already exists, use `NewVersion.s.sol`.
contract Deploy is BaseScript {
    PlaceholderSetup public placeholderSetup;

    function run() external {
        _requireMetadata();
        address pluginRepoFactory = vm.envAddress("PLUGIN_REPO_FACTORY_ADDRESS");
        address managementDao = vm.envAddress("MANAGEMENT_DAO_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        multisigRepo = PluginRepoFactory(pluginRepoFactory).createPluginRepo(_ensSubdomain(), deployer);
        multisigSetup = new MultisigSetup();
        _publish(
            multisigRepo,
            address(multisigSetup),
            bytes(PluginSettings.BUILD_METADATA),
            bytes(PluginSettings.RELEASE_METADATA)
        );

        // Not used by anyone: deployed only so that explorers verify their source code, which then
        // also applies to the instances created by the setup and the factory.
        new ListedCheckCondition(multisigSetup.implementation());
        new ERC1967Proxy(address(multisigRepo), "");

        _transferOwnership(multisigRepo, managementDao, deployer);

        vm.stopBroadcast();

        console.log("- Multisig PluginRepo:  ", address(multisigRepo));
        console.log("- MultisigSetup:        ", address(multisigSetup));
        console.log("- Implementation:       ", multisigSetup.implementation());
        if (address(placeholderSetup) != address(0)) {
            console.log("- PlaceholderSetup:     ", address(placeholderSetup));
        }
        console.log(
            "- Version:              ", _versionString(PluginSettings.VERSION_RELEASE, PluginSettings.VERSION_BUILD)
        );

        _writeArtifact(managementDao, address(multisigSetup), multisigSetup.implementation());
    }

    /// @dev `MULTISIG_ENS_SUBDOMAIN` for production ("multisig"); a unique name otherwise, so that
    ///      test deployments never collide with the canonical one.
    function _ensSubdomain() internal view returns (string memory subdomain) {
        subdomain = vm.envOr("MULTISIG_ENS_SUBDOMAIN", string(""));
        if (bytes(subdomain).length == 0) {
            subdomain = string.concat("multisig-", vm.toString(block.timestamp));
        }
        console.log("- ENS subdomain:        ", subdomain);
    }

    /// @dev Fills builds `1..VERSION_BUILD - 1` with a placeholder so that build numbers are the same
    ///      on every network, then publishes `_setup` as `VERSION_BUILD`. Expects an empty repo.
    function _publish(PluginRepo _repo, address _setup, bytes memory _buildMetadata, bytes memory _releaseMetadata)
        internal
    {
        uint256 latestBuild = _repo.buildCount(PluginSettings.VERSION_RELEASE);
        if (latestBuild != 0) revert InvalidVersionBuild(PluginSettings.VERSION_BUILD, latestBuild);

        if (PluginSettings.VERSION_BUILD > 1) {
            placeholderSetup = new PlaceholderSetup();
            for (uint8 i = 1; i < PluginSettings.VERSION_BUILD; ++i) {
                _repo.createVersion(
                    PluginSettings.VERSION_RELEASE,
                    address(placeholderSetup),
                    bytes(PluginSettings.PLACEHOLDER_BUILD_METADATA),
                    _releaseMetadata
                );
            }
        }

        _repo.createVersion(PluginSettings.VERSION_RELEASE, _setup, _buildMetadata, _releaseMetadata);
    }

    /// @dev Grants ROOT, MAINTAINER and UPGRADE_REPO on the repo to the management DAO and revokes
    ///      them from the deployer, in one call.
    function _transferOwnership(PluginRepo _repo, address _managementDao, address _deployer) internal {
        bytes32[3] memory permissionIds =
            [_repo.ROOT_PERMISSION_ID(), _repo.MAINTAINER_PERMISSION_ID(), _repo.UPGRADE_REPO_PERMISSION_ID()];

        PermissionLib.MultiTargetPermission[] memory permissions = new PermissionLib.MultiTargetPermission[](6);
        for (uint256 i; i < 3; ++i) {
            permissions[i] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Grant,
                where: address(_repo),
                who: _managementDao,
                condition: PermissionLib.NO_CONDITION,
                permissionId: permissionIds[i]
            });
            permissions[i + 3] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Revoke,
                where: address(_repo),
                who: _deployer,
                condition: PermissionLib.NO_CONDITION,
                permissionId: permissionIds[i]
            });
        }

        _repo.applyMultiTargetPermissions(permissions);
    }
}
