// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {IPermissionCondition} from "@aragon/osx-commons-contracts/src/permission/condition/IPermissionCondition.sol";

import {Multisig} from "../../../../../src/Multisig.sol";
import {SelectorCondition} from "../../../../utils/mocks/SelectorCondition.sol";

contract Approve_Multisig_UnitTest is BaseTest {
    uint256 internal proposalId;

    function setUp() public override {
        super.setUp();
        proposalId = _createProposal(alice);
    }

    function _approvals(uint256 _proposalId) internal view returns (uint16 approvals) {
        (, approvals,,,,) = multisig.getProposal(_proposalId);
    }

    function _executed(uint256 _proposalId) internal view returns (bool executed) {
        (executed,,,,,) = multisig.getProposal(_proposalId);
    }

    function test_WhenAMemberApproves() external {
        // it should record the approval and emit Approved.
        vm.expectEmit(address(multisig));
        emit Multisig.Approved(proposalId, bob);
        _approve(proposalId, bob);

        assertEq(_approvals(proposalId), 1, "approvals");
        assertTrue(multisig.hasApproved(proposalId, bob), "hasApproved");
        assertFalse(multisig.hasApproved(proposalId, alice), "others untouched");
    }

    function test_RevertWhen_ApprovingTwice() external {
        // it should revert.
        _approve(proposalId, bob);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, proposalId, bob));
        _approve(proposalId, bob);
    }

    function test_RevertWhen_CallerIsNotAMember() external {
        // it should revert.
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, proposalId, dave));
        _approve(proposalId, dave);
    }

    function test_RevertWhen_ProposalDoesNotExist() external {
        // it should revert with ApprovalCastForbidden (not NonexistentProposal).
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, 123, bob));
        _approve(123, bob);
    }

    function test_RevertWhen_ProposalHasNotStarted() external {
        // it should revert.
        vm.prank(alice);
        uint256 futureId = multisig.createProposal(
            "future", _actions(1), 0, false, false, uint64(block.timestamp) + 1, uint64(block.timestamp) + 2
        );
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, futureId, bob));
        _approve(futureId, bob);

        vm.warp(block.timestamp + 1);
        _approve(futureId, bob);
        assertEq(_approvals(futureId), 1, "approvable at exactly startDate");
    }

    function test_WhenApprovingAtExactlyTheEndDate() external {
        // it should accept the approval.
        vm.warp(block.timestamp + PROPOSAL_DURATION);
        _approve(proposalId, bob);
        assertEq(_approvals(proposalId), 1);
    }

    function test_RevertWhen_ApprovingAfterTheEndDate() external {
        // it should revert.
        vm.warp(block.timestamp + PROPOSAL_DURATION + 1);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, proposalId, bob));
        _approve(proposalId, bob);
    }

    function test_RevertWhen_ProposalWasExecuted() external {
        // it should revert.
        vm.roll(block.number + 1); // the fixture already created the default proposal in this block
        uint256 passedId = _createPassedProposal();
        multisig.execute(passedId);
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, passedId, carol));
        _approve(passedId, carol);
    }

    // ==== Snapshot semantics (finding F7) ====

    function test_RevertWhen_MemberWasAddedAfterCreation() external {
        // it should revert, eligibility is fixed at the snapshot block.
        vm.roll(block.number + 1);
        _addMembers(_members(dave));
        vm.roll(block.number + 1);

        assertTrue(multisig.isListed(dave), "listed now");
        vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, proposalId, dave));
        _approve(proposalId, dave);
    }

    function test_WhenMemberWasRemovedAfterCreation() external {
        // it should still accept the approval (finding F7).
        vm.roll(block.number + 1);
        _removeMembers(_members(carol));
        vm.roll(block.number + 1);

        assertFalse(multisig.isListed(carol), "not listed now");
        _approve(proposalId, carol);
        assertTrue(multisig.hasApproved(proposalId, carol));
    }

    function test_WhenMemberWasRemovedInTheCreationBlock() external {
        // it should still accept the approval, the snapshot is the block before creation.
        _removeMembers(_members(carol));
        uint256 sameBlockId = _createProposal(alice, _actions(2), 0, false, false);
        _approve(sameBlockId, carol);
        assertTrue(multisig.hasApproved(sameBlockId, carol));
    }

    // ==== tryExecution ====

    function test_WhenTryExecutionAndThresholdIsNotMet() external {
        // it should only record the approval.
        vm.prank(bob);
        multisig.approve(proposalId, true);
        assertEq(_approvals(proposalId), 1, "approvals");
        assertFalse(_executed(proposalId), "executed");
    }

    function test_WhenTryExecutionAndThresholdIsMet() external {
        // it should execute and emit Approved and ProposalExecuted.
        _approve(proposalId, alice);

        vm.expectEmit(address(multisig));
        emit Multisig.Approved(proposalId, bob);
        vm.expectEmit(address(multisig));
        emit IProposal.ProposalExecuted(proposalId);
        vm.prank(bob);
        multisig.approve(proposalId, true);

        assertTrue(_executed(proposalId), "executed");
        assertEq(actionTarget.value(), 1, "action ran");
    }

    function test_WhenNoTryExecutionAndThresholdIsMet() external {
        // it should not execute.
        _approve(proposalId, alice);
        _approve(proposalId, bob);
        assertFalse(_executed(proposalId), "executed");
        assertTrue(multisig.canExecute(proposalId), "executable");
    }

    function test_WhenTryExecutionWithoutExecutePermission() external {
        // it should record the approval and not execute, without reverting.
        _revoke(address(multisig), ANY_ADDR, EXECUTE_PROPOSAL_PERMISSION_ID);
        _approve(proposalId, alice);

        vm.prank(bob);
        multisig.approve(proposalId, true);

        assertEq(_approvals(proposalId), 2, "approvals");
        assertFalse(_executed(proposalId), "executed");
    }

    function test_RevertWhen_TryExecutionAndAnActionReverts() external {
        // it should revert the approval itself (finding F4: IMultisig says it does not revert).
        // FINDING: F4. IMultisig.approve NatSpec says tryExecution does not revert on failure; it does.
        Action[] memory actionList = new Action[](1);
        actionList[0] = _failingAction();
        uint256 failingId = _createProposal(alice, actionList, 0, true, false);

        vm.expectRevert(abi.encodeWithSelector(DAO.ActionFailed.selector, 0));
        vm.prank(bob);
        multisig.approve(failingId, true);

        assertEq(_approvals(failingId), 1, "approval rolled back");
        assertFalse(multisig.hasApproved(failingId, bob), "bob not recorded");

        // Approving without execution works.
        _approve(failingId, bob);
        assertEq(_approvals(failingId), 2, "approval without try");
    }

    function test_WhenTryExecutionAndTheExecuteConditionChecksTheSelector() external {
        // it should forward the approve calldata to the condition (finding F5).
        // FINDING: F5. The EXECUTE_PROPOSAL check in approve() passes the outer msg.data, not execute(id).
        _revoke(address(multisig), ANY_ADDR, EXECUTE_PROPOSAL_PERMISSION_ID);
        SelectorCondition executeOnly = new SelectorCondition(Multisig.execute.selector);
        vm.prank(manager);
        dao.grantWithCondition(
            address(multisig), ANY_ADDR, EXECUTE_PROPOSAL_PERMISSION_ID, IPermissionCondition(address(executeOnly))
        );

        _approve(proposalId, alice);
        vm.prank(bob);
        multisig.approve(proposalId, true);
        assertFalse(_executed(proposalId), "condition saw approve calldata, no execution");

        vm.prank(carol);
        multisig.execute(proposalId);
        assertTrue(_executed(proposalId), "direct execute passes the condition");
    }

    function test_WhenTryExecutionAndTheConditionOnlyAllowsTheApproveSelector() external {
        // it should execute through approve although direct execution is denied (finding F5).
        _revoke(address(multisig), ANY_ADDR, EXECUTE_PROPOSAL_PERMISSION_ID);
        SelectorCondition approveOnly = new SelectorCondition(Multisig.approve.selector);
        vm.prank(manager);
        dao.grantWithCondition(
            address(multisig), ANY_ADDR, EXECUTE_PROPOSAL_PERMISSION_ID, IPermissionCondition(address(approveOnly))
        );

        _approve(proposalId, alice);
        _approve(proposalId, bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(multisig), carol, EXECUTE_PROPOSAL_PERMISSION_ID
            )
        );
        vm.prank(carol);
        multisig.execute(proposalId);

        vm.prank(carol);
        multisig.approve(proposalId, true);
        assertTrue(_executed(proposalId), "executed through approve");
    }
}
