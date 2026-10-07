// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginSetupRef, hashHelpers} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PluginUpgradeableSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginUpgradeableSetup.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import {Multisig} from "../../src/Multisig.sol";
import {ActionTarget} from "../utils/mocks/ActionTarget.sol";
import {ForkBaseTest} from "./ForkBaseTest.t.sol";

/// @dev Installations of every published build, updated to this repository's code through the live PSP.
///      Each test leaves a proposal pending across the update, as real DAOs would have.
contract Update_ForkTest is ForkBaseTest {
    bytes internal constant UPDATE_METADATA = "ipfs://updated-plugin-metadata";

    DAO internal dao;
    Multisig internal multisig;
    uint256 internal pendingId;

    /// @dev Installs `_build`, then creates a proposal approved by alice only (threshold 2).
    function _installAndCreatePending(uint16 _build) internal {
        // Some networks published placeholders for builds that never existed there (e.g. build 1 on sepolia).
        if (PluginUpgradeableSetup(multisigRepo.getVersion(_tag(_build)).pluginSetup).implementation() == address(0)) {
            vm.skip(true, string.concat("build ", vm.toString(_build), " is a placeholder on this network"));
        }
        bytes memory data = _build < 3 ? _legacyInstallData(_members(), 2) : _installData(_members(), 2);
        address plugin;
        (dao, plugin) = _createDao(_tag(_build), data);
        multisig = Multisig(plugin);
        vm.roll(block.number + 1);

        Action[] memory actions = new Action[](1);
        actions[0] = Action({to: address(actionTarget), value: 0, data: abi.encodeCall(ActionTarget.setValue, (7))});
        // Same 7-argument selector in every build.
        vm.prank(alice);
        pendingId =
            multisig.createProposal("ipfs://pending", actions, 0, true, false, 0, uint64(block.timestamp + 7 days));
        vm.roll(block.number + 1);
    }

    function _legacyUpdateData() internal pure returns (bytes memory) {
        return
            abi.encode(IPlugin.TargetConfig({target: address(0), operation: IPlugin.Operation.Call}), UPDATE_METADATA);
    }

    function _assertUpdatedState(uint16 _fromBuild) internal view {
        address m = address(multisig);
        assertEq(multisig.implementation(), localSetup.implementation(), "implementation");
        assertEq(multisig.addresslistLength(), 3, "members kept");
        (bool onlyListed, uint16 minApprovals) = multisig.multisigSettings();
        assertTrue(onlyListed, "onlyListed kept");
        assertEq(minApprovals, 2, "minApprovals kept");
        (, uint16 approvals,,,,) = multisig.getProposal(pendingId);
        assertEq(approvals, 1, "pending approvals kept");

        assertFalse(dao.hasPermission(m, address(dao), UPGRADE_PLUGIN_PERMISSION_ID, ""), "DAO cannot upgrade");
        assertFalse(dao.hasPermission(m, address(psp), UPGRADE_PLUGIN_PERMISSION_ID, ""), "PSP cannot upgrade");
        assertFalse(dao.hasPermission(address(dao), address(psp), ROOT_PERMISSION_ID, ""), "PSP has no ROOT");
        assertTrue(dao.hasPermission(m, alice, CREATE_PROPOSAL_PERMISSION_ID, ""), "create: member");
        assertFalse(dao.hasPermission(m, address(0xBEEF), CREATE_PROPOSAL_PERMISSION_ID, ""), "create: outsider");
        assertTrue(dao.hasPermission(m, address(0xBEEF), EXECUTE_PROPOSAL_PERMISSION_ID, ""), "execute: anyone");
        assertTrue(dao.hasPermission(m, address(dao), SET_TARGET_CONFIG_PERMISSION_ID, ""), "target config");
        assertTrue(dao.hasPermission(m, address(dao), SET_METADATA_PERMISSION_ID, ""), "metadata");
        if (_fromBuild < 3) assertEq(multisig.getMetadata(), UPDATE_METADATA, "metadata set by initializeFrom");
    }

    function _assertNewProposalsWork() internal {
        Action[] memory actions = new Action[](1);
        actions[0] = Action({to: address(actionTarget), value: 0, data: abi.encodeCall(ActionTarget.setValue, (99))});
        vm.prank(bob);
        uint256 id = multisig.createProposal("ipfs://new", actions, 0, true, false, 0, uint64(block.timestamp + 1 days));
        vm.prank(carol);
        multisig.approve(id, true);
        assertEq(actionTarget.value(), 99, "new proposal executed");
    }

    // ==== From builds 1 and 2 ====

    function _updateFromLegacy(uint16 _build) internal {
        _installAndCreatePending(_build);
        (IPluginSetup.PreparedSetupData memory prepared, bytes memory initData) =
            _update(dao, address(multisig), _tag(_build), installedHelpers, _legacyUpdateData());

        assertEq(prepared.helpers.length, 1, "new condition");
        assertEq(initData, abi.encodeCall(Multisig.initializeFrom, (_build, _legacyUpdateData())), "initData");
        _assertUpdatedState(_build);
    }

    function test_WhenUpdatingFromBuild1() external {
        // it should upgrade, reinitialize and rewire the permissions; members, settings and approvals are kept.
        _updateFromLegacy(1);
        _assertNewProposalsWork();
    }

    function test_WhenUpdatingFromBuild2() external {
        // it should upgrade, reinitialize and rewire the permissions; members, settings and approvals are kept.
        _updateFromLegacy(2);
        _assertNewProposalsWork();
    }

    function test_RevertWhen_ExecutingAProposalCreatedOnBuild1() external {
        // it should revert although canExecute is true (finding F1).
        _updateFromLegacy(1);
        _assertPendingIsBricked();
    }

    function test_RevertWhen_ExecutingAProposalCreatedOnBuild2() external {
        // it should revert although canExecute is true (finding F1).
        _updateFromLegacy(2);
        _assertPendingIsBricked();
    }

    function test_RevertWhen_ExecutingAProposalCreatedOnBuild2AfterUpdatingToThePublishedBuild3() external {
        // it should revert too: the bug is already live in build 3 (finding F1).
        _installAndCreatePending(2);
        _update(dao, address(multisig), _tag(2), _tag(3), installedHelpers, _legacyUpdateData());
        assertEq(
            multisig.implementation(),
            PluginUpgradeableSetup(multisigRepo.getVersion(_tag(3)).pluginSetup).implementation(),
            "live build 3"
        );
        _assertPendingIsBricked();
    }

    /// @dev FINDING: F1. Builds 1 and 2 stored no `targetConfig` per proposal. `_execute(uint256)` uses the
    ///      stored (empty) target instead of falling back to the DAO, so it calls `address(0)` and reverts.
    ///      The proposal can still be approved and `canExecute` reports true, but it can never execute:
    ///      it has to be recreated after the update.
    function _assertPendingIsBricked() internal {
        (,,,,, IPlugin.TargetConfig memory stored) = multisig.getProposal(pendingId);
        assertEq(stored.target, address(0), "no stored target");

        vm.prank(bob);
        multisig.approve(pendingId, false);
        assertTrue(multisig.canExecute(pendingId), "reported as executable");

        vm.prank(carol);
        vm.expectRevert();
        multisig.execute(pendingId);

        vm.prank(carol);
        vm.expectRevert();
        multisig.approve(pendingId, true); // same through tryExecution (carol is the third member)

        (bool executed,,,,,) = multisig.getProposal(pendingId);
        assertFalse(executed, "never executed");
        assertEq(actionTarget.value(), 0, "action never ran");
    }

    function test_RevertWhen_UpdatingFromALegacyBuildWithoutData() external {
        // it should revert when applying: initializeFrom needs (targetConfig, metadata) (R1).
        _installAndCreatePending(2);
        vm.expectRevert();
        this.externalUpdate(_tag(2), "");
    }

    function externalUpdate(PluginRepo.Tag memory _fromTag, bytes memory _data) external {
        _update(dao, address(multisig), _fromTag, installedHelpers, _data);
    }

    // ==== From build 3 ====

    function test_WhenUpdatingFromBuild3WithTheUpgradePermissionBracket() external {
        // it should upgrade the implementation without reinitializing or changing permissions.
        _installAndCreatePending(3);
        (IPluginSetup.PreparedSetupData memory prepared, bytes memory initData) =
            _update(dao, address(multisig), _tag(3), installedHelpers, "");

        assertEq(initData.length, 0, "no reinitialization");
        assertEq(prepared.permissions.length, 0, "no permission changes");
        _assertUpdatedState(3);
        _executePending();
        _assertNewProposalsWork();
    }

    function test_RevertWhen_UpdatingFromBuild3WithoutGrantingUpgradeToThePsp() external {
        // it should revert: build 3 does not let the DAO or the PSP upgrade the plugin by default (R2).
        _installAndCreatePending(3);
        vm.startPrank(address(dao));
        dao.grant(address(dao), address(psp), ROOT_PERMISSION_ID);
        (bytes memory initData, IPluginSetup.PreparedSetupData memory prepared) = psp.prepareUpdate(
            address(dao),
            PluginSetupProcessor.PrepareUpdateParams({
                currentVersionTag: _tag(3),
                newVersionTag: localTag,
                pluginSetupRepo: multisigRepo,
                setupPayload: IPluginSetup.SetupPayload({
                    plugin: address(multisig), currentHelpers: installedHelpers, data: ""
                })
            })
        );
        vm.expectRevert();
        psp.applyUpdate(
            address(dao),
            PluginSetupProcessor.ApplyUpdateParams({
                plugin: address(multisig),
                pluginSetupRef: PluginSetupRef({versionTag: localTag, pluginSetupRepo: multisigRepo}),
                initData: initData,
                permissions: prepared.permissions,
                helpersHash: hashHelpers(prepared.helpers)
            })
        );
        vm.stopPrank();
    }

    // ==== Helpers ====

    function _executePending() internal {
        vm.prank(bob);
        multisig.approve(pendingId, false);
        vm.prank(carol);
        multisig.execute(pendingId);
        (bool executed,,,,,) = multisig.getProposal(pendingId);
        assertTrue(executed, "executed");
        assertEq(actionTarget.value(), 7, "pending action ran");
        assertEq(actionTarget.lastCaller(), address(dao), "through the DAO");
    }
}
