// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

contract HasApproved_Multisig_UnitTest is BaseTest {
    uint256 internal proposalId;

    function setUp() public override {
        super.setUp();
        proposalId = _createProposal(alice);
    }

    function test_WhenAccountHasNotApproved() external view {
        // it should return false.
        assertFalse(multisig.hasApproved(proposalId, bob));
    }

    function test_WhenAccountHasApproved() external {
        // it should return true for that account only.
        _approve(proposalId, bob);
        assertTrue(multisig.hasApproved(proposalId, bob), "bob");
        assertFalse(multisig.hasApproved(proposalId, alice), "alice");
    }

    function test_WhenApprovedViaCreation() external {
        // it should return true for the creator.
        vm.roll(block.number + 1);
        uint256 approvedId = _createProposal(alice, _actions(1), 0, true, false);
        assertTrue(multisig.hasApproved(approvedId, alice));
    }

    function test_WhenProposalDoesNotExist() external view {
        // it should return false without reverting (finding F11).
        assertFalse(multisig.hasApproved(42, alice));
    }

    function test_WhenApproverWasRemovedAfterwards() external {
        // it should keep returning true.
        _approve(proposalId, carol);
        vm.roll(block.number + 1);
        _removeMembers(_members(carol));
        assertTrue(multisig.hasApproved(proposalId, carol));
    }
}
