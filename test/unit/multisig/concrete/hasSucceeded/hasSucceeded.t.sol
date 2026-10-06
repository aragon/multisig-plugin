// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {Multisig} from "../../../../../src/Multisig.sol";

contract HasSucceeded_Multisig_UnitTest is BaseTest {
    function test_RevertWhen_ProposalDoesNotExist() external {
        // it should revert with NonexistentProposal.
        vm.expectRevert(abi.encodeWithSelector(Multisig.NonexistentProposal.selector, 3));
        multisig.hasSucceeded(3);
    }

    function test_WhenBelowThreshold() external {
        // it should return false.
        uint256 proposalId = _createProposal(alice, _actions(1), 0, true, false);
        assertFalse(multisig.hasSucceeded(proposalId));
    }

    function test_WhenThresholdIsMet() external {
        // it should return true.
        uint256 proposalId = _createPassedProposal();
        assertTrue(multisig.hasSucceeded(proposalId));
    }

    function test_WhenExecuted() external {
        // it should still return true (finding F11).
        uint256 proposalId = _createPassedProposal();
        multisig.execute(proposalId);
        assertTrue(multisig.hasSucceeded(proposalId));
    }

    function test_WhenExpiredAfterPassing() external {
        // it should still return true (finding F11).
        uint256 proposalId = _createPassedProposal();
        vm.warp(block.timestamp + PROPOSAL_DURATION + 1);
        assertTrue(multisig.hasSucceeded(proposalId));
    }

    function test_WhenExpiredWithoutPassing() external {
        // it should return false.
        uint256 proposalId = _createProposal(alice, _actions(1), 0, true, false);
        vm.warp(block.timestamp + PROPOSAL_DURATION + 1);
        assertFalse(multisig.hasSucceeded(proposalId));
    }

    function test_WhenMinApprovalsChangedAfterCreation() external {
        // it should use the stored minApprovals.
        uint256 proposalId = _createProposal(alice, _actions(1), 0, true, false);
        _updateSettings(true, 1);
        assertFalse(multisig.hasSucceeded(proposalId));
    }
}
