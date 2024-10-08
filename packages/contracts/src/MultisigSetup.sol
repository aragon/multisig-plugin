// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

/* solhint-disable max-line-length */
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PluginUpgradeableSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginUpgradeableSetup.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";

import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

import {ListedCheckCondition} from "./ListedCheckCondition.sol";

import {Multisig} from "./Multisig.sol";

/* solhint-enable max-line-length */

/// @title MultisigSetup
/// @author Aragon X - 2022-2023
/// @notice The setup contract of the `Multisig` plugin.
/// @dev v1.3 (Release 1, Build 3)
/// @custom:security-contact sirt@aragon.org
contract MultisigSetup is PluginUpgradeableSetup {
    using ProxyLib for address;

    /// @notice The ID of the permission required to call the `execute` function.
    bytes32 internal constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");

    /// @notice The ID of the permission required to call the `upgradeToAndCall` function.
    bytes32 internal constant UPGRADE_PLUGIN_PERMISSION_ID = keccak256("UPGRADE_PLUGIN_PERMISSION");

    /// @notice The ID of the permission required to call the `setTargetConfig` function.
    bytes32 public constant SET_TARGET_CONFIG_PERMISSION_ID =
        keccak256("SET_TARGET_CONFIG_PERMISSION");

    /// @notice The ID of the permission required to call the `updateMultisigSettings` function.
    bytes32 public constant UPDATE_MULTISIG_SETTINGS_PERMISSION_ID =
        keccak256("UPDATE_MULTISIG_SETTINGS_PERMISSION");

    /// @notice The contract constructor, that deploys the `Multisig` plugin logic contract.
    constructor() PluginUpgradeableSetup(address(new Multisig())) {}

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes calldata _data
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        // Decode `_data` to extract the params needed for deploying and initializing `Multisig` plugin.
        (
            address[] memory members,
            Multisig.MultisigSettings memory multisigSettings,
            PluginUUPSUpgradeable.TargetConfig memory targetConfig,
            bytes memory metadata
        ) = abi.decode(
                _data,
                (address[], Multisig.MultisigSettings, PluginUUPSUpgradeable.TargetConfig, bytes)
            );

        // Deploy and initialize the plugin UUPS proxy.
        plugin = IMPLEMENTATION.deployUUPSProxy(
            abi.encodeCall(
                Multisig.initialize,
                (IDAO(_dao), members, multisigSettings, targetConfig, metadata)
            )
        );

        address listedCheckCondition = address(new ListedCheckCondition(plugin));

        // Prepare permissions
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](4);

        // Set permissions to be granted.
        // Grant the list of permissions of the plugin to the DAO.
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _dao,
            who: plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });

        permissions[2] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.GrantWithCondition,
            plugin,
            address(type(uint160).max), // ANY_ADDR
            listedCheckCondition,
            Multisig(IMPLEMENTATION).CREATE_PROPOSAL_PERMISSION_ID()
        );

        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: SET_TARGET_CONFIG_PERMISSION_ID
        });

        preparedSetupData.permissions = permissions;

        preparedSetupData.helpers = new address[](1);
        preparedSetupData.helpers[0] = listedCheckCondition;
    }

    /// @inheritdoc IPluginSetup
    /// @dev Revoke the upgrade plugin permission to the DAO for all builds prior the current one (3).
    function prepareUpdate(
        address _dao,
        uint16 _fromBuild,
        SetupPayload calldata _payload
    )
        external
        override
        returns (bytes memory initData, PreparedSetupData memory preparedSetupData)
    {
        (initData);

        if (_fromBuild < 3) {
            address listedCheckCondition = address(new ListedCheckCondition(_payload.plugin));

            PermissionLib.MultiTargetPermission[]
                memory permissions = new PermissionLib.MultiTargetPermission[](3);

            permissions[0] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Revoke,
                where: _payload.plugin,
                who: _dao,
                condition: PermissionLib.NO_CONDITION,
                permissionId: UPGRADE_PLUGIN_PERMISSION_ID
            });

            permissions[1] = PermissionLib.MultiTargetPermission(
                PermissionLib.Operation.GrantWithCondition,
                _payload.plugin,
                address(type(uint160).max), // ANY_ADDR
                listedCheckCondition,
                Multisig(IMPLEMENTATION).CREATE_PROPOSAL_PERMISSION_ID()
            );

            permissions[2] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Grant,
                where: _payload.plugin,
                who: _dao,
                condition: PermissionLib.NO_CONDITION,
                permissionId: SET_TARGET_CONFIG_PERMISSION_ID
            });

            preparedSetupData.permissions = permissions;

            preparedSetupData.helpers = new address[](1);
            preparedSetupData.helpers[0] = listedCheckCondition;

            initData = abi.encodeCall(Multisig.initializeFrom, (_fromBuild, _payload.data));
        }
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external view returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        // Prepare permissions
        permissions = new PermissionLib.MultiTargetPermission[](4);

        // Set permissions to be Revoked.
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _dao,
            who: _payload.plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });

        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: SET_TARGET_CONFIG_PERMISSION_ID
        });

        permissions[3] = PermissionLib.MultiTargetPermission(
            PermissionLib.Operation.Revoke,
            _payload.plugin,
            address(type(uint160).max), // ANY_ADDR
            PermissionLib.NO_CONDITION,
            Multisig(IMPLEMENTATION).CREATE_PROPOSAL_PERMISSION_ID()
        );
    }
}
