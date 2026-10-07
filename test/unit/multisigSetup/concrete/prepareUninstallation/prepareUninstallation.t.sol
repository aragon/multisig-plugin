// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {MultisigSetupBaseTest} from "../../MultisigSetupBaseTest.t.sol";

import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";

import {ListedCheckCondition} from "../../../../../src/ListedCheckCondition.sol";

contract PrepareUninstallation_MultisigSetup_UnitTest is MultisigSetupBaseTest {
    function _prepare(address _plugin, address[] memory _helpers, bytes memory _data)
        internal
        view
        returns (PermissionLib.MultiTargetPermission[] memory)
    {
        return setup.prepareUninstallation(
            address(dao), IPluginSetup.SetupPayload({plugin: _plugin, currentHelpers: _helpers, data: _data})
        );
    }

    function test_WhenPreparingTheUninstallation() external view {
        // it should return exactly 6 revocations mirroring the installation, in this order.
        address[] memory helpers = new address[](1);
        helpers[0] = address(listedCheckCondition);
        PermissionLib.MultiTargetPermission[] memory p = _prepare(address(multisig), helpers, "");
        address plugin = address(multisig);

        assertEq(p.length, 6, "length");
        _assertPermission(
            p[0],
            PermissionLib.Operation.Revoke,
            plugin,
            address(dao),
            NO_CONDITION,
            UPDATE_MULTISIG_SETTINGS_PERMISSION_ID,
            "0"
        );
        _assertPermission(
            p[1], PermissionLib.Operation.Revoke, address(dao), plugin, NO_CONDITION, EXECUTE_PERMISSION_ID, "1"
        );
        _assertPermission(
            p[2],
            PermissionLib.Operation.Revoke,
            plugin,
            address(dao),
            NO_CONDITION,
            SET_TARGET_CONFIG_PERMISSION_ID,
            "2"
        );
        _assertPermission(
            p[3], PermissionLib.Operation.Revoke, plugin, address(dao), NO_CONDITION, SET_METADATA_PERMISSION_ID, "3"
        );
        _assertPermission(
            p[4], PermissionLib.Operation.Revoke, plugin, ANY_ADDR, NO_CONDITION, CREATE_PROPOSAL_PERMISSION_ID, "4"
        );
        _assertPermission(
            p[5], PermissionLib.Operation.Revoke, plugin, ANY_ADDR, NO_CONDITION, EXECUTE_PROPOSAL_PERMISSION_ID, "5"
        );
    }

    function test_WhenHelpersAndDataVary() external view {
        // it should return the same list regardless of helpers and data.
        PermissionLib.MultiTargetPermission[] memory a = _prepare(address(multisig), new address[](0), "");
        PermissionLib.MultiTargetPermission[] memory b = _prepare(address(multisig), new address[](3), hex"deadbeef");
        assertEq(keccak256(abi.encode(a)), keccak256(abi.encode(b)));
    }

    function test_WhenAppliedAfterTheFixtureInstallation() external {
        // it should leave no permission behind (the conditional CREATE_PROPOSAL grant included).
        PermissionLib.MultiTargetPermission[] memory p = _prepare(address(multisig), new address[](0), "");
        vm.prank(manager);
        dao.applyMultiTargetPermissions(p);

        address plugin = address(multisig);
        assertFalse(dao.hasPermission(plugin, address(dao), UPDATE_MULTISIG_SETTINGS_PERMISSION_ID, ""), "settings");
        assertFalse(dao.hasPermission(address(dao), plugin, EXECUTE_PERMISSION_ID, ""), "execute");
        assertFalse(dao.hasPermission(plugin, address(dao), SET_TARGET_CONFIG_PERMISSION_ID, ""), "target");
        assertFalse(dao.hasPermission(plugin, address(dao), SET_METADATA_PERMISSION_ID, ""), "metadata");
        assertFalse(dao.hasPermission(plugin, alice, CREATE_PROPOSAL_PERMISSION_ID, ""), "create");
        assertFalse(dao.hasPermission(plugin, alice, EXECUTE_PROPOSAL_PERMISSION_ID, ""), "execute proposal");
        // The conditional slot is cleared: granting it again with another condition does not hit
        // PermissionAlreadyGrantedForDifferentCondition.
        ListedCheckCondition otherCondition = new ListedCheckCondition(plugin);
        vm.prank(manager);
        dao.grantWithCondition(plugin, ANY_ADDR, CREATE_PROPOSAL_PERMISSION_ID, otherCondition);
    }
}
