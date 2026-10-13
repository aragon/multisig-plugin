// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {Multisig} from "../../../../../src/Multisig.sol";

contract CanExecute_Multisig_UnitTest is BaseTest {
    function test_RevertWhen_ProposalDoesNotExist() external {
        // it should revert with NonexistentProposal.
        vm.expectRevert(abi.encodeWithSelector(Multisig.NonexistentProposal.selector, 7));
        multisig.canExecute(7);
    }

    function test_WhenBelowThreshold() external {
        // it should return false.
        uint256 proposalId = _createProposal(alice, _actions(1), 0, true, false);
        assertFalse(multisig.canExecute(proposalId));
    }

    function test_WhenThresholdIsMet() external {
        // it should return true.
        uint256 proposalId = _createPassedProposal();
        assertTrue(multisig.canExecute(proposalId));
    }

    function test_WhenThresholdIsExceeded() external {
        // it should return true.
        uint256 proposalId = _createPassedProposal();
        _approve(proposalId, carol);
        assertTrue(multisig.canExecute(proposalId));
    }

    function test_WhenExecuted() external {
        // it should return false.
        uint256 proposalId = _createPassedProposal();
        multisig.execute(proposalId);
        assertFalse(multisig.canExecute(proposalId));
    }

    function test_WhenNotStarted() external {
        // it should return false, approvals are impossible before the start anyway.
        uint64 start = uint64(block.timestamp) + 100;
        vm.prank(alice);
        uint256 proposalId = multisig.createProposal("future", _actions(1), 0, false, false, start, start + 100);
        assertFalse(multisig.canExecute(proposalId));
    }

    function test_WhenPassedAndAtExactlyTheEndDate() external {
        // it should return true.
        uint256 proposalId = _createPassedProposal();
        vm.warp(block.timestamp + PROPOSAL_DURATION);
        assertTrue(multisig.canExecute(proposalId));
    }

    function test_WhenPassedButExpired() external {
        // it should return false, the proposal is stuck forever.
        uint256 proposalId = _createPassedProposal();
        vm.warp(block.timestamp + PROPOSAL_DURATION + 1);
        assertFalse(multisig.canExecute(proposalId));
        assertTrue(multisig.hasSucceeded(proposalId), "succeeded but not executable");
    }

    function test_WhenMinApprovalsIsRaisedAfterCreation() external {
        // it should keep using the minApprovals stored in the proposal.
        uint256 proposalId = _createPassedProposal();
        _updateSettings(true, 3);
        assertTrue(multisig.canExecute(proposalId));
    }

    function test_WhenMinApprovalsIsLoweredAfterCreation() external {
        // it should keep requiring the stored minApprovals.
        uint256 proposalId = _createProposal(alice, _actions(1), 0, true, false);
        _updateSettings(true, 1);
        assertFalse(multisig.canExecute(proposalId));
    }
}
