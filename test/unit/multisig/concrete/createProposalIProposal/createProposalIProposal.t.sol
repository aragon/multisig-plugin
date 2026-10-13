// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import {Multisig} from "../../../../../src/Multisig.sol";

/// @notice The generic `IProposal.createProposal(bytes,Action[],uint64,uint64,bytes)` overload.
contract CreateProposalIProposal_Multisig_UnitTest is BaseTest {
    function _create(address _creator, Action[] memory _actionList, bytes memory _data) internal returns (uint256) {
        vm.prank(_creator);
        return IProposal(address(multisig))
            .createProposal(PROPOSAL_METADATA, _actionList, 0, uint64(block.timestamp) + PROPOSAL_DURATION, _data);
    }

    function test_WhenDataIsEmpty() external {
        // it should use failure map 0, no approval and no execution.
        uint256 proposalId = _create(alice, _actions(1), "");

        (bool executed, uint16 approvals,,, uint256 allowFailureMap,) = multisig.getProposal(proposalId);
        assertFalse(executed, "executed");
        assertEq(approvals, 0, "approvals");
        assertEq(allowFailureMap, 0, "map");
        assertFalse(multisig.hasApproved(proposalId, alice), "hasApproved");
    }

    function test_WhenDataSetsAllCustomParameters() external {
        // it should apply the failure map, approve and execute.
        _updateSettings(true, 1);
        vm.roll(block.number + 1);

        uint256 proposalId = _create(alice, _actions(1), abi.encode(uint256(1), true, true));

        (bool executed, uint16 approvals,,, uint256 allowFailureMap,) = multisig.getProposal(proposalId);
        assertTrue(executed, "executed");
        assertEq(approvals, 1, "approvals");
        assertEq(allowFailureMap, 1, "map");
        assertEq(actionTarget.value(), 1, "action ran");
    }

    function test_WhenDataApprovesWithoutTryingExecution() external {
        // it should approve only.
        _updateSettings(true, 1);
        vm.roll(block.number + 1);

        uint256 proposalId = _create(alice, _actions(1), abi.encode(uint256(0), true, false));
        (bool executed, uint16 approvals,,,,) = multisig.getProposal(proposalId);
        assertFalse(executed, "executed");
        assertEq(approvals, 1, "approvals");
        assertTrue(multisig.canExecute(proposalId), "executable");
    }

    function test_RevertWhen_DataIsMalformed() external {
        // it should revert while decoding.
        Action[] memory actionList = _actions(1);
        vm.expectRevert();
        _create(alice, actionList, abi.encode(uint256(1)));
    }

    function test_WhenDataHasTrailingBytes() external {
        // it should ignore them (abi.decode accepts longer input).
        uint256 proposalId = _create(alice, _actions(1), abi.encode(uint256(3), false, false, uint256(42)));
        (,,,, uint256 allowFailureMap,) = multisig.getProposal(proposalId);
        assertEq(allowFailureMap, 3);
    }

    function test_RevertWhen_CallerIsNotAllowed() external {
        // it should revert, the permission check of the 7-argument function still applies.
        Action[] memory actionList = _actions(1);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(multisig), dave, CREATE_PROPOSAL_PERMISSION_ID
            )
        );
        _create(dave, actionList, "");
    }

    function test_WhenCreated_ItShouldMatchThe7ArgumentOverload() external {
        // it should produce the same ID and emit ProposalCreated with the caller as creator.
        Action[] memory actionList = _actions(2);
        uint256 expectedId = _expectedProposalId(actionList, PROPOSAL_METADATA);
        uint64 end = uint64(block.timestamp) + PROPOSAL_DURATION;

        vm.expectEmit(address(multisig));
        emit IProposal.ProposalCreated(
            expectedId, alice, uint64(block.timestamp), end, PROPOSAL_METADATA, actionList, 0
        );
        assertEq(_create(alice, actionList, ""), expectedId);
    }

    function test_WhenStartDateIsInThePast() external {
        // it should revert like the 7-argument overload.
        vm.warp(block.timestamp + 10);
        Action[] memory actionList = _actions(1);
        uint64 start = uint64(block.timestamp) - 1;
        vm.expectRevert(abi.encodeWithSelector(Multisig.DateOutOfBounds.selector, uint64(block.timestamp), start));
        vm.prank(alice);
        IProposal(address(multisig)).createProposal(PROPOSAL_METADATA, actionList, start, start + 100, "");
    }
}
