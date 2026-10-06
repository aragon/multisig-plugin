// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {Action, IExecutor} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import {Multisig} from "../../../../../src/Multisig.sol";
import {IMultisig} from "../../../../../src/IMultisig.sol";
import {ActionTarget} from "../../../../utils/mocks/ActionTarget.sol";
import {CustomExecutorMock} from "../../../../utils/mocks/CustomExecutorMock.sol";

contract Execute_Multisig_UnitTest is BaseTest {
    function _executed(uint256 _proposalId) internal view returns (bool executed) {
        (executed,,,,,) = multisig.getProposal(_proposalId);
    }

    /// @dev Creates a proposal with the given actions and failure map, approved by alice and bob.
    function _passed(Action[] memory _actionList, uint256 _map) internal returns (uint256 proposalId) {
        proposalId = _createProposal(alice, _actionList, _map, true, false);
        _approve(proposalId, bob);
    }

    function _setTarget(address _target, IPlugin.Operation _operation) internal {
        vm.prank(address(dao));
        multisig.setTargetConfig(IPlugin.TargetConfig({target: _target, operation: _operation}));
    }

    // ==== Preconditions ====

    function test_RevertWhen_ProposalDoesNotExist() external {
        // it should revert with ProposalExecutionForbidden.
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, 5));
        multisig.execute(5);
    }

    function test_RevertWhen_BelowThreshold() external {
        // it should revert.
        uint256 proposalId = _createProposal(alice, _actions(1), 0, true, false);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, proposalId));
        multisig.execute(proposalId);
    }

    function test_RevertWhen_AlreadyExecuted() external {
        // it should revert.
        uint256 proposalId = _createPassedProposal();
        multisig.execute(proposalId);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, proposalId));
        multisig.execute(proposalId);
    }

    function test_WhenAtExactlyTheEndDate() external {
        // it should execute.
        uint256 proposalId = _createPassedProposal();
        vm.warp(block.timestamp + PROPOSAL_DURATION);
        multisig.execute(proposalId);
        assertTrue(_executed(proposalId));
    }

    function test_RevertWhen_Expired() external {
        // it should revert.
        uint256 proposalId = _createPassedProposal();
        vm.warp(block.timestamp + PROPOSAL_DURATION + 1);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, proposalId));
        multisig.execute(proposalId);
    }

    function test_RevertWhen_ExecutePermissionIsRevoked() external {
        // it should revert with DaoUnauthorized.
        uint256 proposalId = _createPassedProposal();
        _revoke(address(multisig), ANY_ADDR, EXECUTE_PROPOSAL_PERMISSION_ID);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(multisig), alice, EXECUTE_PROPOSAL_PERMISSION_ID
            )
        );
        vm.prank(alice);
        multisig.execute(proposalId);
    }

    function test_WhenCallerIsNotAMember() external {
        // it should execute, the permission is granted to any address by default.
        uint256 proposalId = _createPassedProposal();
        vm.prank(unauthorized);
        multisig.execute(proposalId);
        assertTrue(_executed(proposalId));
    }

    // ==== Effects ====

    function test_WhenPassed_ItShouldExecuteOnTheDao() external {
        // it should run the actions through the DAO and emit Executed and ProposalExecuted.
        Action[] memory actionList = _actions(2);
        uint256 proposalId = _passed(actionList, 0);

        bytes[] memory execResults = new bytes[](2);
        vm.expectEmit(address(dao));
        emit IExecutor.Executed(address(multisig), bytes32(proposalId), actionList, 0, 0, execResults);
        vm.expectEmit(address(multisig));
        emit IProposal.ProposalExecuted(proposalId);
        multisig.execute(proposalId);

        assertTrue(_executed(proposalId), "executed");
        assertEq(actionTarget.value(), 2, "last action ran");
        assertEq(actionTarget.lastCaller(), address(dao), "called by the DAO");
    }

    function test_WhenAnActionTransfersValue() external {
        // it should transfer the DAO's native tokens.
        vm.deal(address(dao), 1 ether);
        Action[] memory actionList = new Action[](1);
        actionList[0] =
            Action({to: address(actionTarget), value: 1 ether, data: abi.encodeCall(ActionTarget.setValue, (9))});
        uint256 proposalId = _passed(actionList, 0);

        multisig.execute(proposalId);
        assertEq(address(actionTarget).balance, 1 ether, "received");
        assertEq(address(dao).balance, 0, "spent");
    }

    function test_WhenAFailingActionIsAllowedByTheFailureMap() external {
        // it should execute and report the failure.
        Action[] memory actionList = new Action[](2);
        actionList[0] = _actions(1)[0];
        actionList[1] = _failingAction();
        uint256 proposalId = _passed(actionList, 1 << 1);

        bytes[] memory execResults = new bytes[](2);
        execResults[1] = abi.encodeWithSelector(ActionTarget.ActionReverted.selector);
        vm.expectEmit(address(dao));
        emit IExecutor.Executed(address(multisig), bytes32(proposalId), actionList, 1 << 1, 1 << 1, execResults);
        multisig.execute(proposalId);

        assertTrue(_executed(proposalId), "executed");
        assertEq(actionTarget.value(), 1, "first action ran");
    }

    function test_RevertWhen_AFailingActionIsNotAllowed() external {
        // it should revert and leave the proposal unexecuted.
        Action[] memory actionList = new Action[](2);
        actionList[0] = _actions(1)[0];
        actionList[1] = _failingAction();
        uint256 proposalId = _passed(actionList, 1); // only the first action may fail

        vm.expectRevert(abi.encodeWithSelector(DAO.ActionFailed.selector, 1));
        multisig.execute(proposalId);

        assertFalse(_executed(proposalId), "rolled back");
        assertTrue(multisig.canExecute(proposalId), "still executable");
    }

    // ==== Target config ====

    function test_WhenTargetIsACustomExecutorWithCall() external {
        // it should call the executor with the plugin as sender.
        CustomExecutorMock executor = new CustomExecutorMock();
        _setTarget(address(executor), IPlugin.Operation.Call);
        vm.roll(block.number + 1);
        uint256 proposalId = _passed(_actions(2), 4);

        vm.expectEmit(address(executor));
        emit CustomExecutorMock.ExecutedCustom(address(executor), address(multisig), bytes32(proposalId), 2, 4);
        vm.prank(carol);
        multisig.execute(proposalId);

        assertTrue(_executed(proposalId), "executed");
        assertEq(actionTarget.value(), 0, "the DAO did not run the actions");
    }

    function test_WhenTargetIsACustomExecutorWithDelegateCall() external {
        // it should run the executor code in the plugin's context.
        CustomExecutorMock executor = new CustomExecutorMock();
        _setTarget(address(executor), IPlugin.Operation.DelegateCall);
        vm.roll(block.number + 1);
        uint256 proposalId = _passed(_actions(1), 0);

        vm.expectEmit(address(multisig));
        emit CustomExecutorMock.ExecutedCustom(address(multisig), carol, bytes32(proposalId), 1, 0);
        vm.prank(carol);
        multisig.execute(proposalId);
        assertTrue(_executed(proposalId));
    }

    function test_RevertWhen_TheCustomExecutorReverts() external {
        // it should bubble up the revert, for both operations.
        CustomExecutorMock executor = new CustomExecutorMock();
        uint256 revertMap = executor.REVERT_FAILURE_MAP();

        _setTarget(address(executor), IPlugin.Operation.Call);
        vm.roll(block.number + 1);
        uint256 callId = _passed(_actions(1), revertMap);
        vm.expectRevert(CustomExecutorMock.FailedCustom.selector);
        multisig.execute(callId);

        _setTarget(address(executor), IPlugin.Operation.DelegateCall);
        vm.roll(block.number + 1);
        uint256 delegateId = _passed(_actions(1), revertMap);
        vm.expectRevert(CustomExecutorMock.FailedCustom.selector);
        multisig.execute(delegateId);
    }

    function test_WhenTargetChangesAfterCreation() external {
        // it should execute on the target stored at creation (finding F6).
        uint256 proposalId = _createPassedProposal();

        CustomExecutorMock executor = new CustomExecutorMock();
        _setTarget(address(executor), IPlugin.Operation.Call);

        multisig.execute(proposalId);
        assertEq(actionTarget.value(), 1, "executed by the old target (DAO)");
        assertEq(actionTarget.lastCaller(), address(dao), "DAO");
    }

    // ==== Reentrancy ====

    function test_RevertWhen_AnActionReentersExecuteOfAnotherProposal() external {
        // it should revert the whole execution: the DAO reentrancy guard makes the action fail.
        uint256 innerId = _createPassedProposal();
        vm.roll(block.number + 1);
        Action[] memory actionList = new Action[](1);
        actionList[0] = _reenterExecuteAction(innerId);
        uint256 outerId = _passed(actionList, 0);

        vm.expectRevert(abi.encodeWithSelector(DAO.ActionFailed.selector, 0));
        multisig.execute(outerId);
        assertFalse(_executed(outerId), "outer rolled back");
        assertFalse(_executed(innerId), "inner rolled back");
    }

    function test_WhenAnActionReentersExecuteOfAnotherProposalAndFailureIsAllowed() external {
        // it should execute the outer proposal, the inner execution fails with ReentrantCall.
        uint256 innerId = _createPassedProposal();
        vm.roll(block.number + 1);
        Action[] memory actionList = new Action[](1);
        actionList[0] = _reenterExecuteAction(innerId);
        uint256 outerId = _passed(actionList, 1);

        bytes[] memory execResults = new bytes[](1);
        execResults[0] = abi.encodeWithSelector(DAO.ReentrantCall.selector);
        vm.expectEmit(address(dao));
        emit IExecutor.Executed(address(multisig), bytes32(outerId), actionList, 1, 1, execResults);
        multisig.execute(outerId);

        assertTrue(_executed(outerId), "outer");
        assertFalse(_executed(innerId), "inner blocked by the DAO reentrancy guard");
        assertTrue(multisig.canExecute(innerId), "inner still executable");
    }

    function test_WhenAnActionReentersApproveAndFailureIsAllowed() external {
        // it should execute, the re-entering approval is forbidden.
        uint256 innerId = _createProposal(alice, _actions(2), 0, false, false);
        vm.roll(block.number + 1);
        Action[] memory actionList = new Action[](1);
        actionList[0] = Action({
            to: address(actionTarget),
            value: 0,
            data: abi.encodeCall(ActionTarget.reenterApprove, (IMultisig(address(multisig)), innerId))
        });
        uint256 outerId = _passed(actionList, 1);

        bytes[] memory execResults = new bytes[](1);
        execResults[0] = abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, innerId, address(actionTarget));
        vm.expectEmit(address(dao));
        emit IExecutor.Executed(address(multisig), bytes32(outerId), actionList, 1, 1, execResults);
        multisig.execute(outerId);
        assertFalse(multisig.hasApproved(innerId, address(actionTarget)));
    }

    function test_WhenTheTargetReentersExecuteForTheSameProposal() external {
        // it should reject the re-entry: the proposal is flagged as executed before the external call.
        // An action cannot reference its own proposal (the ID hashes the actions), so a custom target re-enters.
        ReenteringExecutor executor = new ReenteringExecutor(multisig);
        _setTarget(address(executor), IPlugin.Operation.Call);
        vm.roll(block.number + 1);
        uint256 proposalId = _passed(_actions(1), 0);

        multisig.execute(proposalId);
        assertTrue(_executed(proposalId), "executed");
        assertEq(
            executor.reentryRevertData(),
            abi.encodeWithSelector(Multisig.ProposalExecutionForbidden.selector, proposalId),
            "re-entry rejected"
        );
    }

    function _reenterExecuteAction(uint256 _proposalId) internal view returns (Action memory) {
        return Action({
            to: address(actionTarget),
            value: 0,
            data: abi.encodeCall(ActionTarget.reenterExecute, (IMultisig(address(multisig)), _proposalId))
        });
    }
}

/// @dev Custom target that tries to execute the same proposal again while being executed.
contract ReenteringExecutor {
    Multisig internal immutable MULTISIG;
    bytes public reentryRevertData;

    constructor(Multisig _multisig) {
        MULTISIG = _multisig;
    }

    function execute(bytes32 _callId, Action[] memory, uint256) external returns (bytes[] memory, uint256) {
        try MULTISIG.execute(uint256(_callId)) {}
        catch (bytes memory reason) {
            reentryRevertData = reason;
        }
        return (new bytes[](0), 0);
    }
}
