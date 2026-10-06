// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {Vm} from "forge-std/Vm.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import {Multisig} from "../../../../../src/Multisig.sol";

/// @notice Burns all the gas it receives: an action that only fails by running out of gas.
contract GasHungryTarget {
    function consume() external pure {
        uint256 i;
        while (true) {
            ++i;
        }
    }
}

/// @dev Limits of execution that come from the DAO executor, seen through the Multisig.
contract ExecuteLimits_Multisig_UnitTest is BaseTest {
    uint256 internal constant DAO_MAX_ACTIONS = 256;

    function _passAndExecute(Action[] memory _actionList, uint256 _allowFailureMap) internal returns (uint256 id) {
        id = _createProposal(alice, _actionList, _allowFailureMap, true, false);
        _approve(id, bob);
        vm.prank(carol);
        multisig.execute(id);
    }

    function test_WhenTheProposalHasTheMaximumNumberOfActions() external {
        // it should execute all 256 actions.
        _passAndExecute(_actions(DAO_MAX_ACTIONS), 0);
        assertEq(actionTarget.value(), DAO_MAX_ACTIONS, "last action ran");
    }

    function test_RevertWhen_TheProposalHasMoreActionsThanTheDaoAccepts() external {
        // it should accept the proposal and let it pass, but it can never execute.
        // FINDING: F22. Multisig does not cap the number of actions at creation; the DAO rejects more than
        // 256 at execution, so such a proposal can gather approvals and never execute.
        uint256 id = _createProposal(alice, _actions(DAO_MAX_ACTIONS + 1), 0, true, false);
        _approve(id, bob);
        assertTrue(multisig.canExecute(id), "reported as executable");

        vm.prank(carol);
        vm.expectRevert(DAO.TooManyActions.selector);
        multisig.execute(id);
    }

    function test_WhenAnActionSendsNativeTokens() external {
        // it should transfer the value from the DAO.
        vm.deal(address(dao), 1 ether);
        Action[] memory actionList = _actions(1);
        actionList[0].value = 0.4 ether;

        _passAndExecute(actionList, 0);
        assertEq(address(actionTarget).balance, 0.4 ether, "received");
        assertEq(address(dao).balance, 0.6 ether, "DAO paid");
    }

    function test_RevertWhen_TheDaoCannotCoverTheValue() external {
        // it should revert the execution, and the proposal stays executable.
        Action[] memory actionList = _actions(1);
        actionList[0].value = 1 ether;
        uint256 id = _createProposal(alice, actionList, 0, true, false);
        _approve(id, bob);

        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(DAO.ActionFailed.selector, 0));
        multisig.execute(id);
        assertTrue(multisig.canExecute(id), "still executable once funded");

        vm.deal(address(dao), 1 ether);
        vm.prank(carol);
        multisig.execute(id);
        assertEq(address(actionTarget).balance, 1 ether, "executed later");
    }

    function test_RevertWhen_TheExecutorStarvesAnActionThatMayFail() external {
        // it should revert instead of recording the action as failed: an executor cannot make an
        // allowed-to-fail action fail on purpose by sending too little gas.
        Action[] memory actionList = new Action[](2);
        actionList[0] =
            Action({to: address(new GasHungryTarget()), value: 0, data: abi.encodeCall(GasHungryTarget.consume, ())});
        actionList[1] = _actions(1)[0];
        uint256 id = _createProposal(alice, actionList, 1, true, false); // action 0 may fail
        _approve(id, bob);

        vm.prank(carol);
        vm.expectRevert(DAO.InsufficientGas.selector);
        multisig.execute{gas: 2_000_000}(id);

        (bool executed,,,,,) = multisig.getProposal(id);
        assertFalse(executed, "not marked executed");
        assertTrue(multisig.canExecute(id), "still executable");
    }

    function test_WhenTheMetadataIsLarge() external {
        // it should accept it and emit it in full.
        bytes memory metadata = new bytes(20_000);
        for (uint256 i; i < metadata.length; ++i) {
            metadata[i] = bytes1(uint8(i));
        }
        Action[] memory actionList = _actions(1);

        vm.recordLogs();
        vm.prank(alice);
        uint256 id = multisig.createProposal(metadata, actionList, 0, false, false, 0, uint64(block.timestamp + 1 days));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes memory emitted;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(multisig) && logs[i].topics[0] == IProposal.ProposalCreated.selector) {
                (,, emitted,,) = abi.decode(logs[i].data, (uint64, uint64, bytes, Action[], uint256));
            }
        }
        assertEq(emitted, metadata, "emitted in full");
        assertEq(id, _expectedProposalId(actionList, metadata), "id covers the full metadata");
    }

    function test_WhenTheProposalHasNoActions() external {
        // it should pass and execute as a no-op (useful for signalling).
        Action[] memory none = new Action[](0);
        uint256 id = _passAndExecute(none, 0);
        (bool executed,,,,,) = multisig.getProposal(id);
        assertTrue(executed, "executed");
    }
}
