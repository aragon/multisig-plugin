// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import {Multisig} from "../../../../../src/Multisig.sol";

contract GetProposal_Multisig_UnitTest is BaseTest {
    function test_WhenProposalDoesNotExist() external view {
        // it should return zeroed data without reverting (finding F11).
        (
            bool executed,
            uint16 approvals,
            Multisig.ProposalParameters memory parameters,
            Action[] memory actionList,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        ) = multisig.getProposal(999);

        assertFalse(executed, "executed");
        assertEq(approvals, 0, "approvals");
        assertEq(parameters.snapshotBlock, 0, "snapshot");
        assertEq(parameters.startDate, 0, "start");
        assertEq(parameters.endDate, 0, "end");
        assertEq(parameters.minApprovals, 0, "minApprovals");
        assertEq(actionList.length, 0, "actions");
        assertEq(allowFailureMap, 0, "map");
        assertEq(targetConfig.target, address(0), "target");
    }

    function test_WhenApprovalsAreCast() external {
        // it should count each approval once.
        uint256 proposalId = _createProposal(alice);
        _approve(proposalId, alice);
        _approve(proposalId, bob);
        _approve(proposalId, carol);
        (, uint16 approvals,,,,) = multisig.getProposal(proposalId);
        assertEq(approvals, 3);
    }

    function test_WhenExecuted() external {
        // it should report executed and keep all other fields.
        uint256 proposalId = _createPassedProposal();
        multisig.execute(proposalId);
        (bool executed, uint16 approvals, Multisig.ProposalParameters memory parameters, Action[] memory actionList,,) =
            multisig.getProposal(proposalId);
        assertTrue(executed, "executed");
        assertEq(approvals, 2, "approvals");
        assertEq(parameters.minApprovals, 2, "minApprovals");
        assertEq(actionList.length, 1, "actions");
    }
}
