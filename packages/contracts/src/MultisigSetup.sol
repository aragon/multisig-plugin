// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

/* solhint-disable max-line-length */
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PluginUpgradeableSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginUpgradeableSetup.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

import {Multisig} from "./Multisig.sol";

/* solhint-enable max-line-length */

/// @title MultisigSetup
/// @author Aragon X - 2022-2023
/// @notice The setup contract of the `Multisig` plugin.
/// @dev v1.3 (Release 1, Build 3)
/// @custom:security-contact sirt@aragon.org
contract MultisigSetup is PluginUpgradeableSetup {
    using ProxyLib for address;

    // TODO This permission identifier will be moved into a library in task OS-954.
    /// @notice The ID of the permission required to call the `execute` function.
    bytes32 internal constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");

    /// @notice The contract constructor, that deploys the `Multisig` plugin logic contract.
    constructor() PluginUpgradeableSetup(address(new Multisig())) {}

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes calldata _data
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        // Decode `_data` to extract the params needed for deploying and initializing `Multisig` plugin.
        (address[] memory members, Multisig.MultisigSettings memory multisigSettings) = abi.decode(
            _data,
            (address[], Multisig.MultisigSettings)
        );

        // Deploy and initialize the plugin UUPS proxy.
        plugin = IMPLEMENTATION.deployUUPSProxy(
            abi.encodeCall(Multisig.initialize, (IDAO(_dao), members, multisigSettings))
        );

        // Prepare permissions
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](2);

        // Set permissions to be granted.
        // Grant the list of permissions of the plugin to the DAO.
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: Multisig(IMPLEMENTATION).UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        });

        // Grant `EXECUTE_PERMISSION` of the DAO to the plugin.
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _dao,
            who: plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });

        preparedSetupData.permissions = permissions;
    }

    /// @inheritdoc IPluginSetup
    /// @dev Revoke the upgrade plugin permission from the DAO for all builds previous to the current one (3).
    function prepareUpdate(
        address _dao,
        uint16 _currentBuild,
        SetupPayload calldata _payload
    )
        external
        view
        override
        returns (bytes memory initData, PreparedSetupData memory preparedSetupData)
    {
        (initData);

        // all builds previous current one (3) have this permission granted and need to be revoked
        if (_currentBuild < 3) {
            PermissionLib.MultiTargetPermission[]
                memory permissions = new PermissionLib.MultiTargetPermission[](1);

            permissions[0] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Revoke,
                where: _payload.plugin,
                who: _dao,
                condition: PermissionLib.NO_CONDITION,
                permissionId: Multisig(IMPLEMENTATION).UPGRADE_PLUGIN_PERMISSION_ID()
            });

            preparedSetupData.permissions = permissions;
        }
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external view returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        // Prepare permissions
        permissions = new PermissionLib.MultiTargetPermission[](2);

        // Set permissions to be Revoked.
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: Multisig(IMPLEMENTATION).UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _dao,
            who: _payload.plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });
    }
}
