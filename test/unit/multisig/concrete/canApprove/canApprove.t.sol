// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {Multisig} from "../../../../../src/Multisig.sol";

contract CanApprove_Multisig_UnitTest is BaseTest {
    uint256 internal proposalId;

    function setUp() public override {
        super.setUp();
        proposalId = _createProposal(alice);
    }

    function test_RevertWhen_ProposalDoesNotExist() external {
        // it should revert with NonexistentProposal.
        vm.expectRevert(abi.encodeWithSelector(Multisig.NonexistentProposal.selector, 1));
        multisig.canApprove(1, alice);
    }

    function test_WhenAccountIsAMemberAtTheSnapshot() external view {
        // it should return true.
        assertTrue(multisig.canApprove(proposalId, alice));
        assertTrue(multisig.canApprove(proposalId, carol));
    }

    function test_WhenAccountIsNotAMember() external view {
        // it should return false.
        assertFalse(multisig.canApprove(proposalId, dave));
        assertFalse(multisig.canApprove(proposalId, address(0)));
    }

    function test_WhenAccountAlreadyApproved() external {
        // it should return false.
        _approve(proposalId, bob);
        assertFalse(multisig.canApprove(proposalId, bob));
    }

    function test_WhenProposalIsExecuted() external {
        // it should return false for everyone.
        vm.roll(block.number + 1);
        uint256 passedId = _createPassedProposal();
        multisig.execute(passedId);
        assertFalse(multisig.canApprove(passedId, carol));
    }

    function test_WhenProposalHasNotStarted() external {
        // it should return false until exactly the start date.
        uint64 start = uint64(block.timestamp) + 100;
        vm.prank(alice);
        uint256 futureId = multisig.createProposal("future", _actions(1), 0, false, false, start, start + 100);

        assertFalse(multisig.canApprove(futureId, bob), "before");
        vm.warp(start - 1);
        assertFalse(multisig.canApprove(futureId, bob), "one second before");
        vm.warp(start);
        assertTrue(multisig.canApprove(futureId, bob), "at start");
    }

    function test_WhenProposalHasEnded() external {
        // it should return true at exactly the end date and false one second later.
        vm.warp(block.timestamp + PROPOSAL_DURATION);
        assertTrue(multisig.canApprove(proposalId, bob), "at end");
        vm.warp(block.timestamp + 1);
        assertFalse(multisig.canApprove(proposalId, bob), "after end");
    }

    function test_WhenMembershipChangesAfterCreation() external {
        // it should follow the snapshot, not the current list (finding F7).
        vm.roll(block.number + 1);
        _addMembers(_members(dave));
        _removeMembers(_members(carol));
        vm.roll(block.number + 1);

        assertFalse(multisig.canApprove(proposalId, dave), "added later");
        assertTrue(multisig.canApprove(proposalId, carol), "removed later");
    }

    function test_WhenMemberWasRemovedAndReAdded() external {
        // it should follow the snapshot for each proposal.
        vm.roll(block.number + 1);
        _removeMembers(_members(carol));
        vm.roll(block.number + 1);
        uint256 withoutCarol = _createProposal(alice, _actions(2), 0, false, false);
        vm.roll(block.number + 1);
        _addMembers(_members(carol));
        vm.roll(block.number + 1);

        assertTrue(multisig.canApprove(proposalId, carol), "listed at first snapshot");
        assertFalse(multisig.canApprove(withoutCarol, carol), "not listed at second snapshot");
    }
}
