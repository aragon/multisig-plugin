// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {MultisigSetupBaseTest} from "../../MultisigSetupBaseTest.t.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";

import {Multisig} from "../../../../../src/Multisig.sol";
import {ListedCheckCondition} from "../../../../../src/ListedCheckCondition.sol";

contract PrepareUpdate_MultisigSetup_UnitTest is MultisigSetupBaseTest {
    function _payload(bytes memory _data) internal view returns (IPluginSetup.SetupPayload memory) {
        return IPluginSetup.SetupPayload({plugin: address(multisig), currentHelpers: new address[](0), data: _data});
    }

    function _updateData() internal view returns (bytes memory) {
        return abi.encode(_daoTarget(), PLUGIN_METADATA);
    }

    function _assertLegacyUpdate(uint16 _fromBuild) internal {
        bytes memory data = _updateData();
        address expectedCondition = vm.computeCreateAddress(address(setup), vm.getNonce(address(setup)));

        (bytes memory initData, IPluginSetup.PreparedSetupData memory prepared) =
            setup.prepareUpdate(address(dao), _fromBuild, _payload(data));

        // it should return initializeFrom(fromBuild, data) as init data, passing the payload data verbatim.
        assertEq(initData, abi.encodeCall(Multisig.initializeFrom, (_fromBuild, data)), "initData");

        // it should deploy a new condition bound to the updated plugin.
        assertEq(prepared.helpers.length, 1, "helpers length");
        assertEq(prepared.helpers[0], expectedCondition, "helper address");
        assertTrue(
            ListedCheckCondition(prepared.helpers[0]).isGranted(address(0), alice, bytes32(0), ""), "bound: member"
        );
        assertFalse(
            ListedCheckCondition(prepared.helpers[0]).isGranted(address(0), dave, bytes32(0), ""), "bound: non member"
        );

        // it should return exactly 5 permissions, in this order.
        PermissionLib.MultiTargetPermission[] memory p = prepared.permissions;
        address plugin = address(multisig);
        assertEq(p.length, 5, "length");
        _assertPermission(
            p[0], PermissionLib.Operation.Revoke, plugin, address(dao), NO_CONDITION, UPGRADE_PLUGIN_PERMISSION_ID, "0"
        );
        _assertPermission(
            p[1],
            PermissionLib.Operation.GrantWithCondition,
            plugin,
            ANY_ADDR,
            prepared.helpers[0],
            CREATE_PROPOSAL_PERMISSION_ID,
            "1"
        );
        _assertPermission(
            p[2],
            PermissionLib.Operation.Grant,
            plugin,
            address(dao),
            NO_CONDITION,
            SET_TARGET_CONFIG_PERMISSION_ID,
            "2"
        );
        _assertPermission(
            p[3], PermissionLib.Operation.Grant, plugin, address(dao), NO_CONDITION, SET_METADATA_PERMISSION_ID, "3"
        );
        _assertPermission(
            p[4], PermissionLib.Operation.Grant, plugin, ANY_ADDR, NO_CONDITION, EXECUTE_PROPOSAL_PERMISSION_ID, "4"
        );
    }

    function test_WhenUpdatingFromBuild1() external {
        _assertLegacyUpdate(1);
    }

    function test_WhenUpdatingFromBuild2() external {
        _assertLegacyUpdate(2);
    }

    function test_WhenUpdatingFromBuild0() external {
        // it should treat it like builds 1 and 2.
        // Note: build numbers start at 1, so the PSP never passes 0. Documented, not a reachable path.
        _assertLegacyUpdate(0);
    }

    function test_WhenUpdatingFromBuild3OrHigher() external {
        // it should return no init data, no permissions and no helpers.
        uint16[3] memory builds = [uint16(3), 4, type(uint16).max];
        uint256 nonce = vm.getNonce(address(setup));
        for (uint256 i; i < builds.length; ++i) {
            (bytes memory initData, IPluginSetup.PreparedSetupData memory prepared) =
                setup.prepareUpdate(address(dao), builds[i], _payload(_updateData()));
            assertEq(initData.length, 0, "initData");
            assertEq(prepared.permissions.length, 0, "permissions");
            assertEq(prepared.helpers.length, 0, "helpers");
        }
        // it should not deploy anything.
        assertEq(vm.getNonce(address(setup)), nonce, "no deployment");
    }

    function test_WhenThePayloadDataIsEmpty() external {
        // it should still prepare the update (the data is not decoded here).
        (bytes memory initData,) = setup.prepareUpdate(address(dao), 1, _payload(""));
        assertEq(initData, abi.encodeCall(Multisig.initializeFrom, (uint16(1), bytes(""))), "initData");

        // it should make the update fail when applied: initializeFrom cannot decode empty data.
        // A build 1/2 proxy is modeled as a proxy whose initializer version is still below 2.
        Multisig bare = Multisig(address(new ERC1967Proxy(address(new Multisig()), "")));
        vm.expectRevert();
        bare.initializeFrom(1, "");
    }

    function test_WhenThePayloadPluginIsArbitrary() external {
        // it should not validate the plugin address (the PSP does).
        address notAPlugin = makeAddr("notAPlugin");
        IPluginSetup.SetupPayload memory payload =
            IPluginSetup.SetupPayload({plugin: notAPlugin, currentHelpers: new address[](0), data: _updateData()});
        (, IPluginSetup.PreparedSetupData memory prepared) = setup.prepareUpdate(address(dao), 1, payload);
        assertEq(prepared.permissions[0].where, notAPlugin, "where");
        // The condition is bound to an address without code, so it reverts on use.
        vm.expectRevert();
        ListedCheckCondition(prepared.helpers[0]).isGranted(address(0), alice, bytes32(0), "");
    }

    function test_WhenThePayloadHasCurrentHelpers() external {
        // it should ignore them: the old condition is neither revoked nor reused.
        address[] memory helpers = new address[](1);
        helpers[0] = address(listedCheckCondition);
        IPluginSetup.SetupPayload memory payload =
            IPluginSetup.SetupPayload({plugin: address(multisig), currentHelpers: helpers, data: _updateData()});
        (, IPluginSetup.PreparedSetupData memory prepared) = setup.prepareUpdate(address(dao), 2, payload);
        assertTrue(prepared.helpers[0] != address(listedCheckCondition), "new helper");
        for (uint256 i; i < prepared.permissions.length; ++i) {
            assertTrue(prepared.permissions[i].condition != address(listedCheckCondition), "old helper unused");
        }
    }
}
