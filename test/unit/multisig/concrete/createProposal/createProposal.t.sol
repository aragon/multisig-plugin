// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {Vm} from "forge-std/Vm.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {Action, IExecutor} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import {Multisig} from "../../../../../src/Multisig.sol";
import {CustomExecutorMock} from "../../../../utils/mocks/CustomExecutorMock.sol";

contract CreateProposal_Multisig_UnitTest is BaseTest {
    function _create(address _creator, Action[] memory _actionList, uint256 _map, uint64 _start, uint64 _end)
        internal
        returns (uint256)
    {
        vm.prank(_creator);
        return multisig.createProposal(PROPOSAL_METADATA, _actionList, _map, false, false, _start, _end);
    }

    function _now() internal view returns (uint64) {
        return uint64(block.timestamp);
    }

    // ==== Permissions ====

    function test_RevertWhen_CallerIsNotListedAndOnlyListedIsTrue() external {
        // it should revert, the ListedCheckCondition denies the permission.
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(multisig), dave, CREATE_PROPOSAL_PERMISSION_ID
            )
        );
        _createProposal(dave);
    }

    function test_WhenCallerIsNotListedAndOnlyListedIsFalse() external {
        // it should create the proposal.
        _updateSettings(false, 2);
        vm.roll(block.number + 1);

        uint256 proposalId = _createProposal(dave);
        (,, Multisig.ProposalParameters memory parameters,,,) = multisig.getProposal(proposalId);
        assertEq(parameters.snapshotBlock, block.number - 1, "created");
    }

    function test_RevertWhen_CreatePermissionIsRevoked() external {
        // it should revert, even for members.
        _revoke(address(multisig), ANY_ADDR, CREATE_PROPOSAL_PERMISSION_ID);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(multisig), alice, CREATE_PROPOSAL_PERMISSION_ID
            )
        );
        _createProposal(alice);
    }

    function test_WhenCallerIsListedNowButNotAtTheSnapshot() external {
        // it should create the proposal (condition uses the live list) but the creator cannot approve it.
        _addMembers(_members(dave)); // same block: dave is listed now, not at block.number - 1

        uint256 proposalId = _createProposal(dave);
        assertFalse(multisig.canApprove(proposalId, dave), "canApprove");

        // Creating and approving in the same block reverts the whole creation.
        Action[] memory actionList = _actions(2);
        uint256 expectedId = _expectedProposalId(actionList, PROPOSAL_METADATA);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, expectedId, dave));
        _createProposal(dave, _actions(2), 0, true, false);
    }

    function test_WhenCallerIsUnlistedAndOnlyListedIsFalseAndApproves() external {
        // it should revert the whole creation, an unlisted creator cannot approve.
        _updateSettings(false, 2);
        vm.roll(block.number + 1);

        Action[] memory actionList = _actions(1);
        uint256 expectedId = _expectedProposalId(actionList, PROPOSAL_METADATA);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, expectedId, dave));
        _createProposal(dave, actionList, 0, true, false);
    }

    // ==== Settings change guard ====

    function test_RevertWhen_SettingsChangedInTheSameBlock() external {
        // it should revert with ProposalCreationForbidden.
        _updateSettings(true, 1);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalCreationForbidden.selector, alice));
        _createProposal(alice);
    }

    function test_WhenSettingsChangedInThePreviousBlock() external {
        // it should create the proposal.
        _updateSettings(true, 1);
        vm.roll(block.number + 1);
        uint256 proposalId = _createProposal(alice);
        (,, Multisig.ProposalParameters memory parameters,,,) = multisig.getProposal(proposalId);
        assertEq(parameters.minApprovals, 1, "new settings apply");
    }

    function test_WhenMembersChangedInTheSameBlock() external {
        // it should create the proposal: member changes do not update lastMultisigSettingsChange.
        _addMembers(_members(dave));
        uint64 lastChange = multisig.lastMultisigSettingsChange();
        uint256 proposalId = _createProposal(alice);

        assertEq(multisig.lastMultisigSettingsChange(), lastChange, "unchanged");
        assertLt(lastChange, block.number, "older");
        assertFalse(multisig.canApprove(proposalId, dave), "dave excluded by snapshot");
    }

    // ==== Dates ====

    function test_WhenStartDateIsZero() external {
        // it should use the current timestamp as start date.
        uint256 proposalId = _create(alice, _actions(1), 0, 0, _now() + 1);
        (,, Multisig.ProposalParameters memory parameters,,,) = multisig.getProposal(proposalId);
        assertEq(parameters.startDate, _now(), "startDate");
        assertEq(parameters.endDate, _now() + 1, "endDate");
    }

    function test_WhenStartDateIsNow() external {
        // it should accept it.
        uint256 proposalId = _create(alice, _actions(1), 0, _now(), _now());
        (,, Multisig.ProposalParameters memory parameters,,,) = multisig.getProposal(proposalId);
        assertEq(parameters.startDate, _now(), "startDate");
        assertEq(parameters.endDate, _now(), "endDate == startDate");
        assertTrue(multisig.canApprove(proposalId, alice), "open for this second");
    }

    function test_WhenStartDateIsInTheFuture() external {
        // it should accept it and keep the proposal closed until then.
        uint64 start = _now() + 1 days;
        uint256 proposalId = _create(alice, _actions(1), 0, start, start + 1 days);
        assertFalse(multisig.canApprove(proposalId, alice), "not started");
        vm.warp(start);
        assertTrue(multisig.canApprove(proposalId, alice), "started");
    }

    function test_RevertWhen_StartDateIsInThePast() external {
        // it should revert.
        uint64 start = _now() - 1;
        vm.expectRevert(abi.encodeWithSelector(Multisig.DateOutOfBounds.selector, _now(), start));
        _create(alice, _actions(1), 0, start, _now() + 1);
    }

    function test_RevertWhen_EndDateIsBeforeStartDate() external {
        // it should revert.
        uint64 start = _now() + 10;
        vm.expectRevert(abi.encodeWithSelector(Multisig.DateOutOfBounds.selector, start, start - 1));
        _create(alice, _actions(1), 0, start, start - 1);
    }

    function test_RevertWhen_EndDateIsZeroAndStartDateIsZero() external {
        // it should revert: the start date resolves to now and the limit reported is now.
        vm.expectRevert(abi.encodeWithSelector(Multisig.DateOutOfBounds.selector, _now(), 0));
        _create(alice, _actions(1), 0, 0, 0);
    }

    function test_WhenEndDateIsTheMaximum() external {
        // it should accept it, there is no maximum duration (finding F15).
        uint256 proposalId = _create(alice, _actions(1), 0, 0, type(uint64).max);
        (,, Multisig.ProposalParameters memory parameters,,,) = multisig.getProposal(proposalId);
        assertEq(parameters.endDate, type(uint64).max);
    }

    // ==== Proposal ID ====

    function test_WhenCreated_ItShouldUseTheDocumentedIdFormula() external {
        // it should derive the ID from chain ID, block number, plugin address, actions and metadata.
        Action[] memory actionList = _actions(2);
        uint256 expectedId = _expectedProposalId(actionList, PROPOSAL_METADATA);
        assertEq(_createProposal(alice, actionList, 0, false, false), expectedId);
    }

    function test_RevertWhen_TheSameProposalIsCreatedTwiceInTheSameBlock() external {
        // it should revert with ProposalAlreadyExists.
        uint256 proposalId = _createProposal(alice);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalAlreadyExists.selector, proposalId));
        _createProposal(bob);
    }

    function test_WhenTheSameProposalIsCreatedInTheNextBlock() external {
        // it should create a proposal with a different ID.
        uint256 first = _createProposal(alice);
        vm.roll(block.number + 1);
        uint256 second = _createProposal(alice);
        assertNotEq(first, second);
    }

    function test_WhenSameActionsAndMetadataButDifferentParametersInTheSameBlock() external {
        // it should give the same ID and block the original creator (finding F3: front-running).
        // FINDING: F3. The ID ignores allowFailureMap, dates and creator, so the same content can be front-run.
        _updateSettings(false, 2);
        vm.roll(block.number + 1);
        Action[] memory actionList = _actions(1);

        // The "attacker" lands first with a permissive failure map and a short window.
        uint256 attackerId = _create(dave, actionList, type(uint256).max, 0, _now());
        uint256 expectedId = _expectedProposalId(actionList, PROPOSAL_METADATA);
        assertEq(attackerId, expectedId, "same id regardless of parameters");

        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalAlreadyExists.selector, expectedId));
        _create(alice, actionList, 0, 0, _now() + PROPOSAL_DURATION);

        (,, Multisig.ProposalParameters memory parameters,, uint256 allowFailureMap,) = multisig.getProposal(expectedId);
        assertEq(allowFailureMap, type(uint256).max, "attacker's failure map");
        assertEq(parameters.endDate, _now(), "attacker's window");
    }

    function test_WhenMetadataDiffers() external {
        // it should give a different ID.
        uint256 first = _createProposal(alice);
        vm.prank(alice);
        uint256 second = multisig.createProposal("other", _actions(1), 0, false, false, 0, _now() + 1);
        assertNotEq(first, second);
    }

    function test_WhenProposalHasNoActions() external {
        // it should create it.
        uint256 proposalId = _create(alice, new Action[](0), 0, 0, _now() + 1);
        (,,, Action[] memory actionList,,) = multisig.getProposal(proposalId);
        assertEq(actionList.length, 0);
    }

    // ==== Stored state ====

    function test_WhenCreated_ItShouldStoreTheProposal() external {
        // it should store snapshot block, dates, minApprovals, actions, failure map and target config.
        Action[] memory actionList = _actions(3);
        uint64 end = _now() + 3 days;
        uint256 proposalId = _create(alice, actionList, 5, 0, end);

        (
            bool executed,
            uint16 approvals,
            Multisig.ProposalParameters memory parameters,
            Action[] memory storedActions,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        ) = multisig.getProposal(proposalId);

        assertFalse(executed, "executed");
        assertEq(approvals, 0, "approvals");
        assertEq(parameters.snapshotBlock, block.number - 1, "snapshot");
        assertEq(parameters.startDate, _now(), "start");
        assertEq(parameters.endDate, end, "end");
        assertEq(parameters.minApprovals, 2, "minApprovals");
        assertEq(allowFailureMap, 5, "map");
        assertEq(storedActions.length, 3, "actions");
        for (uint256 i; i < 3; ++i) {
            assertEq(storedActions[i].to, actionList[i].to, "to");
            assertEq(storedActions[i].value, actionList[i].value, "value");
            assertEq(storedActions[i].data, actionList[i].data, "data");
        }
        assertEq(targetConfig.target, address(dao), "target");
        assertEq(uint8(targetConfig.operation), uint8(IPlugin.Operation.Call), "operation");
        assertTrue(multisig.canApprove(proposalId, alice), "alice");
        assertTrue(multisig.canApprove(proposalId, bob), "bob");
    }

    function test_WhenTargetIsUnset_ItShouldStoreTheResolvedDaoTarget() external {
        // it should snapshot the effective target (the DAO), not the zero address.
        vm.prank(address(dao));
        multisig.setTargetConfig(IPlugin.TargetConfig({target: address(0), operation: IPlugin.Operation.Call}));

        uint256 proposalId = _createProposal(alice);
        (,,,,, IPlugin.TargetConfig memory targetConfig) = multisig.getProposal(proposalId);
        assertEq(targetConfig.target, address(dao));
    }

    function test_WhenACustomTargetIsSet_ItShouldStoreIt() external {
        // it should snapshot the custom target and operation.
        IPlugin.TargetConfig memory custom = IPlugin.TargetConfig({
            target: address(new CustomExecutorMock()), operation: IPlugin.Operation.DelegateCall
        });
        vm.prank(address(dao));
        multisig.setTargetConfig(custom);

        uint256 proposalId = _createProposal(alice);
        (,,,,, IPlugin.TargetConfig memory targetConfig) = multisig.getProposal(proposalId);
        assertEq(targetConfig.target, custom.target, "target");
        assertEq(uint8(targetConfig.operation), uint8(IPlugin.Operation.DelegateCall), "operation");
    }

    // ==== Events ====

    function test_WhenCreated_ItShouldEmitProposalCreated() external {
        // it should emit ProposalCreated with all parameters.
        Action[] memory actionList = _actions(2);
        uint256 expectedId = _expectedProposalId(actionList, PROPOSAL_METADATA);
        uint64 end = _now() + 1 days;

        vm.expectEmit(address(multisig));
        emit IProposal.ProposalCreated(expectedId, alice, _now(), end, PROPOSAL_METADATA, actionList, 7);
        vm.prank(alice);
        multisig.createProposal(PROPOSAL_METADATA, actionList, 7, false, false, 0, end);
    }

    function test_WhenCreatedWithApproval() external {
        // it should record the creator's approval and emit Approved.
        Action[] memory actionList = _actions(1);
        uint256 expectedId = _expectedProposalId(actionList, PROPOSAL_METADATA);

        vm.expectEmit(address(multisig));
        emit Multisig.Approved(expectedId, alice);
        uint256 proposalId = _createProposal(alice, actionList, 0, true, false);

        (, uint16 approvals,,,,) = multisig.getProposal(proposalId);
        assertEq(approvals, 1, "approvals");
        assertTrue(multisig.hasApproved(proposalId, alice), "hasApproved");
        assertFalse(multisig.canApprove(proposalId, alice), "cannot approve twice");
    }

    function test_WhenCreatedWithApprovalAndTryExecutionBelowThreshold() external {
        // it should not execute.
        uint256 proposalId = _createProposal(alice, _actions(1), 0, true, true);
        (bool executed,,,,,) = multisig.getProposal(proposalId);
        assertFalse(executed);
        assertEq(actionTarget.value(), 0);
    }

    function test_WhenCreatedWithApprovalAndTryExecutionAtThreshold() external {
        // it should execute, emitting ProposalCreated last (finding F10).
        // FINDING: F10. Indexers see Approved and ProposalExecuted before ProposalCreated.
        _updateSettings(true, 1);
        vm.roll(block.number + 1);

        vm.recordLogs();
        uint256 proposalId = _createProposal(alice, _actions(1), 0, true, true);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (bool executed,,,,,) = multisig.getProposal(proposalId);
        assertTrue(executed, "executed");
        assertEq(actionTarget.value(), 1, "action ran");

        bytes32[] memory expected = new bytes32[](4);
        expected[0] = Multisig.Approved.selector;
        expected[1] = IExecutor.Executed.selector;
        expected[2] = IProposal.ProposalExecuted.selector;
        expected[3] = IProposal.ProposalCreated.selector;

        uint256 found;
        for (uint256 i; i < logs.length && found < expected.length; ++i) {
            if (logs[i].emitter != address(multisig) && logs[i].emitter != address(dao)) continue;
            if (logs[i].topics[0] == expected[found]) found++;
        }
        assertEq(found, expected.length, "event order: Approved, Executed, ProposalExecuted, ProposalCreated");
    }
}
