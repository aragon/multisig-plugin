// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../BaseTest.t.sol";

import {Multisig} from "../../../src/Multisig.sol";
import {MultisigHandler} from "./MultisigHandler.sol";

/// @notice Stateful invariants of the Multisig plugin under random sequences of membership changes,
///         settings updates, proposal creation, approvals, executions and time travel.
contract Multisig_InvariantTest is BaseTest {
    MultisigHandler internal handler;

    function setUp() public override {
        super.setUp();

        address[] memory actors = new address[](8);
        actors[0] = alice;
        actors[1] = bob;
        actors[2] = carol;
        actors[3] = dave;
        actors[4] = makeAddr("erin");
        actors[5] = makeAddr("frank");
        actors[6] = makeAddr("grace");
        actors[7] = unauthorized;

        handler = new MultisigHandler(multisig, dao, actionTarget, actors, _members(alice, bob, carol));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 80
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_MinApprovalsWithinMemberCount() external view {
        // (a) 1 <= minApprovals <= addresslistLength.
        (, uint16 minApprovals) = multisig.multisigSettings();
        assertGe(minApprovals, 1, "minApprovals >= 1");
        assertLe(minApprovals, multisig.addresslistLength(), "minApprovals <= length");
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 80
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ApprovalsMatchApprovers() external view {
        // (b) approvals == number of actors with hasApproved, and every one of them is a tracked approver.
        uint256 proposals = handler.proposalCount();
        uint256 actors = handler.actorCount();
        for (uint256 p; p < proposals; ++p) {
            uint256 proposalId = handler.proposalIds(p);
            (, uint16 approvals,,,,) = multisig.getProposal(proposalId);

            uint256 counted;
            for (uint256 a; a < actors; ++a) {
                address actor = handler.actors(a);
                bool approved = multisig.hasApproved(proposalId, actor);
                assertEq(approved, handler.ghostApproved(proposalId, actor), "hasApproved matches ghost");
                if (approved) counted++;
            }
            assertEq(approvals, counted, "approvals == approvers");
            assertEq(approvals, handler.ghostApprovals(proposalId), "approvals == ghost");
        }
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 80
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ApprovalsBoundedBySnapshotMembers() external view {
        // (c) approvals <= addresslistLengthAtBlock(snapshotBlock).
        uint256 proposals = handler.proposalCount();
        for (uint256 p; p < proposals; ++p) {
            uint256 proposalId = handler.proposalIds(p);
            (, uint16 approvals, Multisig.ProposalParameters memory parameters,,,) = multisig.getProposal(proposalId);
            assertLe(approvals, multisig.addresslistLengthAtBlock(parameters.snapshotBlock), "approvals <= snapshot");
        }
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 80
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ExecutedAtMostOnceAndOnlyWhenPassed() external view {
        // (d) no double execution, executed flag consistent with the ghost.
        // (e) executed only with approvals >= the proposal's minApprovals.
        uint256 proposals = handler.proposalCount();
        for (uint256 p; p < proposals; ++p) {
            uint256 proposalId = handler.proposalIds(p);
            (bool executed, uint16 approvals, Multisig.ProposalParameters memory parameters,,,) =
                multisig.getProposal(proposalId);
            uint256 executions = handler.ghostExecutions(proposalId);

            assertLe(executions, 1, "executed at most once");
            assertEq(executed, executions == 1, "executed flag matches ghost");
            if (executed) {
                assertGe(approvals, parameters.minApprovals, "executed only when passed");
                assertFalse(multisig.canExecute(proposalId), "executed proposal not executable");
            }
        }
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 80
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_MemberListMatchesGhost() external view {
        // (f) addresslistLength equals the ghost member count, and membership matches per actor.
        assertEq(multisig.addresslistLength(), handler.ghostMemberCount(), "length == ghost");
        uint256 actors = handler.actorCount();
        for (uint256 a; a < actors; ++a) {
            address actor = handler.actors(a);
            assertEq(multisig.isListed(actor), handler.ghostListed(actor), "listed == ghost");
            assertEq(multisig.isMember(actor), handler.ghostListed(actor), "member == ghost");
        }
    }
}
