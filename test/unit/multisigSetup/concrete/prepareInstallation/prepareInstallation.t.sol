// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {MultisigSetupBaseTest} from "../../MultisigSetupBaseTest.t.sol";

import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";
import {Addresslist} from "@aragon/osx-commons-contracts/src/plugin/extensions/governance/Addresslist.sol";

import {Multisig} from "../../../../../src/Multisig.sol";
import {ListedCheckCondition} from "../../../../../src/ListedCheckCondition.sol";
import {CustomExecutorMock} from "../../../../utils/mocks/CustomExecutorMock.sol";

contract PrepareInstallation_MultisigSetup_UnitTest is MultisigSetupBaseTest {
    function _prepare(bytes memory _data)
        internal
        returns (address plugin, IPluginSetup.PreparedSetupData memory prepared)
    {
        return setup.prepareInstallation(address(dao), _data);
    }

    function test_WhenPreparingWithValidData() external {
        // it should deploy a UUPS proxy pointing at the setup's implementation.
        // it should deploy the condition right after the proxy.
        uint256 nonce = vm.getNonce(address(setup));
        address expectedPlugin = vm.computeCreateAddress(address(setup), nonce);
        address expectedCondition = vm.computeCreateAddress(address(setup), nonce + 1);

        (address plugin, IPluginSetup.PreparedSetupData memory prepared) = _prepare(_defaultInstallData());

        assertEq(plugin, expectedPlugin, "plugin address");
        assertEq(prepared.helpers.length, 1, "helpers length");
        assertEq(prepared.helpers[0], expectedCondition, "helper address");
        assertEq(
            address(uint160(uint256(vm.load(plugin, IMPLEMENTATION_SLOT)))), setup.implementation(), "implementation"
        );
        assertEq(Multisig(plugin).implementation(), setup.implementation(), "implementation()");
        assertEq(uint8(Multisig(plugin).pluginType()), uint8(IPlugin.PluginType.UUPS), "pluginType");
    }

    function test_WhenPreparingWithValidData_ItShouldInitializeThePlugin() external {
        // it should store the DAO, members, settings, target config and metadata.
        CustomExecutorMock executor = new CustomExecutorMock();
        IPlugin.TargetConfig memory target =
            IPlugin.TargetConfig({target: address(executor), operation: IPlugin.Operation.DelegateCall});
        (address pluginAddress,) =
            _prepare(_installData(_members(alice, bob, carol), false, 3, target, PLUGIN_METADATA));
        Multisig plugin = Multisig(pluginAddress);

        assertEq(address(plugin.dao()), address(dao), "dao");
        assertEq(plugin.addresslistLength(), 3, "length");
        assertTrue(plugin.isListed(alice) && plugin.isListed(bob) && plugin.isListed(carol), "members");
        assertFalse(plugin.isListed(dave), "non member");
        (bool onlyListed, uint16 minApprovals) = plugin.multisigSettings();
        assertFalse(onlyListed, "onlyListed");
        assertEq(minApprovals, 3, "minApprovals");
        assertEq(plugin.getCurrentTargetConfig().target, address(executor), "target");
        assertEq(uint8(plugin.getCurrentTargetConfig().operation), uint8(IPlugin.Operation.DelegateCall), "op");
        assertEq(plugin.getMetadata(), PLUGIN_METADATA, "metadata");
    }

    function test_WhenPreparingWithValidData_ItShouldReturnTheExactPermissions() external {
        // it should return exactly 6 permissions, in this order.
        (address plugin, IPluginSetup.PreparedSetupData memory prepared) = _prepare(_defaultInstallData());
        address condition = prepared.helpers[0];
        PermissionLib.MultiTargetPermission[] memory p = prepared.permissions;

        assertEq(p.length, 6, "length");
        _assertPermission(
            p[0],
            PermissionLib.Operation.Grant,
            plugin,
            address(dao),
            NO_CONDITION,
            UPDATE_MULTISIG_SETTINGS_PERMISSION_ID,
            "0"
        );
        _assertPermission(
            p[1], PermissionLib.Operation.Grant, address(dao), plugin, NO_CONDITION, EXECUTE_PERMISSION_ID, "1"
        );
        _assertPermission(
            p[2],
            PermissionLib.Operation.GrantWithCondition,
            plugin,
            ANY_ADDR,
            condition,
            CREATE_PROPOSAL_PERMISSION_ID,
            "2"
        );
        _assertPermission(
            p[3],
            PermissionLib.Operation.Grant,
            plugin,
            address(dao),
            NO_CONDITION,
            SET_TARGET_CONFIG_PERMISSION_ID,
            "3"
        );
        _assertPermission(
            p[4], PermissionLib.Operation.Grant, plugin, address(dao), NO_CONDITION, SET_METADATA_PERMISSION_ID, "4"
        );
        _assertPermission(
            p[5], PermissionLib.Operation.Grant, plugin, ANY_ADDR, NO_CONDITION, EXECUTE_PROPOSAL_PERMISSION_ID, "5"
        );
    }

    function test_WhenPreparingWithValidData_ItShouldNotGrantUpgradePermission() external {
        // it should not grant UPGRADE_PLUGIN_PERMISSION (removed in build 3).
        (, IPluginSetup.PreparedSetupData memory prepared) = _prepare(_defaultInstallData());
        for (uint256 i; i < prepared.permissions.length; ++i) {
            assertTrue(prepared.permissions[i].permissionId != UPGRADE_PLUGIN_PERMISSION_ID, "upgrade permission");
        }
    }

    function test_WhenPreparingWithValidData_ItShouldBindTheHelperToTheNewPlugin() external {
        // it should return a ListedCheckCondition reading the new plugin's list and settings.
        (address plugin, IPluginSetup.PreparedSetupData memory prepared) =
            _prepare(_installData(_members(dave), true, 1, _daoTarget(), PLUGIN_METADATA));
        ListedCheckCondition condition = ListedCheckCondition(prepared.helpers[0]);

        // dave is a member of the new plugin only, alice of the fixture plugin only.
        assertTrue(condition.isGranted(plugin, dave, CREATE_PROPOSAL_PERMISSION_ID, ""), "dave");
        assertFalse(condition.isGranted(plugin, alice, CREATE_PROPOSAL_PERMISSION_ID, ""), "alice");

        // Live binding: a settings change on the new plugin is reflected (permissions are not applied in a
        // unit test, so grant the settings permission by hand).
        _grant(plugin, address(dao), UPDATE_MULTISIG_SETTINGS_PERMISSION_ID);
        vm.prank(address(dao));
        Multisig(plugin).updateMultisigSettings(_settings(false, 1));
        assertTrue(condition.isGranted(plugin, alice, CREATE_PROPOSAL_PERMISSION_ID, ""), "alice, open");
    }

    function test_WhenPreparingTwice() external {
        // it should deploy a new plugin and condition every time (no auth, permissionless).
        vm.prank(unauthorized);
        (address pluginA, IPluginSetup.PreparedSetupData memory a) =
            setup.prepareInstallation(address(dao), _defaultInstallData());
        (address pluginB, IPluginSetup.PreparedSetupData memory b) = _prepare(_defaultInstallData());
        assertTrue(pluginA != pluginB, "plugins");
        assertTrue(a.helpers[0] != b.helpers[0], "helpers");
    }

    function test_WhenTheDaoAddressIsArbitrary() external {
        // it should not validate the DAO address (no code check).
        address notADao = makeAddr("notADao");
        (address plugin,) = setup.prepareInstallation(
            notADao,
            _installData(
                _members(alice),
                true,
                1,
                IPlugin.TargetConfig({target: notADao, operation: IPlugin.Operation.Call}),
                PLUGIN_METADATA
            )
        );
        assertEq(address(Multisig(plugin).dao()), notADao);
    }

    function test_WhenMetadataIsEmpty() external {
        // it should accept empty plugin metadata.
        (address plugin,) = _prepare(_installData(_members(alice), true, 1, _daoTarget(), ""));
        assertEq(Multisig(plugin).getMetadata(), "");
    }

    function test_RevertWhen_DataIsEmpty() external {
        // it should revert while decoding.
        vm.expectRevert();
        _prepare("");
    }

    function test_RevertWhen_DataIsTruncated() external {
        // it should revert while decoding.
        bytes memory data = _defaultInstallData();
        bytes memory truncated = new bytes(data.length - 32);
        for (uint256 i; i < truncated.length; ++i) {
            truncated[i] = data[i];
        }
        vm.expectRevert();
        _prepare(truncated);
    }

    function test_WhenDataHasTrailingBytes() external {
        // it should ignore them (abi.decode is lenient on extra data).
        (address plugin,) = _prepare(bytes.concat(_defaultInstallData(), hex"deadbeef"));
        assertEq(Multisig(plugin).addresslistLength(), 3);
    }

    function test_RevertWhen_DataUsesAWrongLayout() external {
        // it should revert when the fields are not encoded in the expected order.
        bytes memory wrong = abi.encode(_settings(true, 1), _members(alice), _daoTarget(), PLUGIN_METADATA);
        vm.expectRevert();
        _prepare(wrong);
    }

    function test_RevertWhen_TheOperationIsOutOfRange() external {
        // it should revert when the encoded operation is not a valid enum value.
        // Same layout as the real data, with operation = 2 (only Call = 0 and DelegateCall = 1 exist).
        bytes memory data =
            abi.encode(_members(alice), _settings(true, 1), _rawTarget(address(dao), 2), PLUGIN_METADATA);
        vm.expectRevert();
        _prepare(data);
    }

    function _rawTarget(address _target, uint8 _operation) internal pure returns (RawTarget memory) {
        return RawTarget({target: _target, operation: _operation});
    }

    struct RawTarget {
        address target;
        uint8 operation;
    }

    function test_RevertWhen_MembersAreEmpty() external {
        // it should revert with MinApprovalsOutOfBounds(0, 1).
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 0, 1));
        _prepare(_installData(new address[](0), true, 1, _daoTarget(), PLUGIN_METADATA));
    }

    function test_RevertWhen_MinApprovalsIsZero() external {
        // it should revert with MinApprovalsOutOfBounds(1, 0).
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 1, 0));
        _prepare(_installData(_members(alice, bob), true, 0, _daoTarget(), PLUGIN_METADATA));
    }

    function test_RevertWhen_MinApprovalsExceedsTheMembers() external {
        // it should revert with MinApprovalsOutOfBounds(members, minApprovals).
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 2, 3));
        _prepare(_installData(_members(alice, bob), true, 3, _daoTarget(), PLUGIN_METADATA));
    }

    function test_RevertWhen_MembersContainDuplicates() external {
        // it should revert.
        vm.expectRevert(abi.encodeWithSelector(Addresslist.InvalidAddresslistUpdate.selector, bob));
        _prepare(_installData(_members(alice, bob, bob), true, 1, _daoTarget(), PLUGIN_METADATA));
    }

    function test_RevertWhen_TheTargetIsTheDaoWithDelegateCall() external {
        // it should revert, the plugin would be bricked.
        IPlugin.TargetConfig memory target =
            IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.DelegateCall});
        vm.expectRevert(abi.encodeWithSelector(PluginUUPSUpgradeable.InvalidTargetConfig.selector, target));
        _prepare(_installData(_members(alice), true, 1, target, PLUGIN_METADATA));
    }
}
