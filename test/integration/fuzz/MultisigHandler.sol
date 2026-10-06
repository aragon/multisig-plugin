// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import {Multisig} from "../../../src/Multisig.sol";
import {ActionTarget} from "../../utils/mocks/ActionTarget.sol";

/// @notice Drives random sequences of membership, settings and proposal operations against a Multisig,
///         and keeps ghost state that the invariants compare against the contract.
/// @dev Every call is wrapped in try/catch: invalid operations are expected to revert and must leave
///      the ghost state untouched.
contract MultisigHandler is Test {
    Multisig public immutable multisig;
    DAO public immutable dao;
    ActionTarget public immutable actionTarget;

    /// @notice Every address that can ever be a member, approver or creator.
    address[] public actors;

    // Ghost membership
    mapping(address => bool) public ghostListed;
    uint256 public ghostMemberCount;

    // Ghost proposals
    uint256[] public proposalIds;
    mapping(uint256 => uint256) public ghostApprovals;
    mapping(uint256 => mapping(address => bool)) public ghostApproved;
    mapping(uint256 => uint256) public ghostExecutions;

    // Call statistics (useful when tuning the invariant run)
    mapping(bytes32 => uint256) public calls;

    constructor(
        Multisig _multisig,
        DAO _dao,
        ActionTarget _actionTarget,
        address[] memory _actors,
        address[] memory _initialMembers
    ) {
        multisig = _multisig;
        dao = _dao;
        actionTarget = _actionTarget;
        actors = _actors;
        for (uint256 i; i < _initialMembers.length; ++i) {
            ghostListed[_initialMembers[i]] = true;
        }
        ghostMemberCount = _initialMembers.length;
    }

    // ==== Views for the invariants ====

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function proposalCount() external view returns (uint256) {
        return proposalIds.length;
    }

    // ==== Membership and settings ====

    function addMember(uint256 _actorSeed) external {
        address actor = _actor(_actorSeed);
        address[] memory list = new address[](1);
        list[0] = actor;

        vm.prank(address(dao));
        try multisig.addAddresses(list) {
            assertFalse(ghostListed[actor], "added an already listed member");
            ghostListed[actor] = true;
            ghostMemberCount++;
            calls["addMember.ok"]++;
        } catch {
            assertTrue(ghostListed[actor], "valid addition reverted");
            calls["addMember.revert"]++;
        }
    }

    function removeMember(uint256 _actorSeed) external {
        address actor = _actor(_actorSeed);
        address[] memory list = new address[](1);
        list[0] = actor;
        (, uint16 minApprovals) = multisig.multisigSettings();

        vm.prank(address(dao));
        try multisig.removeAddresses(list) {
            assertTrue(ghostListed[actor], "removed a non member");
            assertGe(ghostMemberCount - 1, minApprovals, "removal below minApprovals");
            ghostListed[actor] = false;
            ghostMemberCount--;
            calls["removeMember.ok"]++;
        } catch {
            calls["removeMember.revert"]++;
        }
    }

    function updateSettings(bool _onlyListed, uint16 _minApprovals) external {
        _minApprovals = uint16(bound(_minApprovals, 0, actors.length + 1));

        vm.prank(address(dao));
        try multisig.updateMultisigSettings(Multisig.MultisigSettings(_onlyListed, _minApprovals)) {
            assertGe(_minApprovals, 1, "accepted zero minApprovals");
            assertLe(_minApprovals, ghostMemberCount, "accepted minApprovals above member count");
            calls["updateSettings.ok"]++;
        } catch {
            assertTrue(_minApprovals == 0 || _minApprovals > ghostMemberCount, "valid settings reverted");
            calls["updateSettings.revert"]++;
        }
    }

    // ==== Proposals ====

    function createProposal(uint256 _actorSeed, uint8 _actionCount, bool _approve, bool _tryExecution, uint32 _duration)
        external
    {
        address creator = _listedActorMostly(_actorSeed);
        Action[] memory actionList = _buildActions(uint8(bound(_actionCount, 0, 3)));
        uint64 endDate = uint64(block.timestamp) + uint64(bound(_duration, 0, 4 days));

        vm.prank(creator);
        try multisig.createProposal("", actionList, 0, _approve, _tryExecution, 0, endDate) returns (
            uint256 proposalId
        ) {
            (bool onlyListed,) = multisig.multisigSettings();
            if (onlyListed) assertTrue(ghostListed[creator], "non member created with onlyListed");
            proposalIds.push(proposalId);
            if (_approve) _recordApproval(proposalId, creator);
            _syncExecution(proposalId);
            calls["createProposal.ok"]++;
        } catch {
            calls["createProposal.revert"]++;
        }
    }

    function approve(uint256 _proposalSeed, uint256 _actorSeed, bool _tryExecution) external {
        if (proposalIds.length == 0) return;
        uint256 proposalId = _approvableMostly(_proposalSeed);
        address approver = _approverMostly(proposalId, _actorSeed);
        bool couldApprove = multisig.canApprove(proposalId, approver);

        vm.prank(approver);
        try multisig.approve(proposalId, _tryExecution) {
            assertTrue(couldApprove, "approved although canApprove was false");
            _recordApproval(proposalId, approver);
            _syncExecution(proposalId);
            calls["approve.ok"]++;
        } catch {
            assertFalse(couldApprove, "approve reverted although canApprove was true");
            calls["approve.revert"]++;
        }
    }

    function execute(uint256 _proposalSeed, uint256 _actorSeed) external {
        if (proposalIds.length == 0) return;
        uint256 proposalId = _executableMostly(_proposalSeed);
        bool couldExecute = multisig.canExecute(proposalId);

        vm.prank(_actor(_actorSeed));
        try multisig.execute(proposalId) {
            assertTrue(couldExecute, "executed although canExecute was false");
            ghostExecutions[proposalId]++;
            calls["execute.ok"]++;
        } catch {
            assertFalse(couldExecute, "execute reverted although canExecute was true");
            calls["execute.revert"]++;
        }
    }

    // ==== Time ====

    function warp(uint32 _seconds) external {
        vm.warp(block.timestamp + bound(_seconds, 0, 12 hours));
        calls["warp"]++;
    }

    function roll(uint8 _blocks) external {
        vm.roll(block.number + bound(_blocks, 1, 5));
        calls["roll"]++;
    }

    // ==== Internal ====

    function _actor(uint256 _seed) internal view returns (address) {
        return actors[_seed % actors.length];
    }

    /// @dev Three times out of four, a currently listed actor (if any), so that creations mostly succeed.
    function _listedActorMostly(uint256 _seed) internal view returns (address) {
        if (_seed % 4 == 0) return _actor(_seed);
        for (uint256 i; i < actors.length; ++i) {
            address candidate = actors[(_seed % actors.length + i) % actors.length];
            if (ghostListed[candidate]) return candidate;
        }
        return _actor(_seed);
    }

    /// @dev Four times out of five, an actor that can approve (if any), so that proposals reach their threshold.
    function _approverMostly(uint256 _proposalId, uint256 _seed) internal view returns (address) {
        if (_seed % 5 == 0) return _actor(_seed);
        for (uint256 i; i < actors.length; ++i) {
            address candidate = actors[(_seed % actors.length + i) % actors.length];
            if (multisig.canApprove(_proposalId, candidate)) return candidate;
        }
        return _actor(_seed);
    }

    /// @dev Four times out of five, a proposal that at least one actor can still approve (if any).
    function _approvableMostly(uint256 _seed) internal view returns (uint256) {
        uint256 length = proposalIds.length;
        if (_seed % 5 != 0) {
            for (uint256 i; i < length; ++i) {
                uint256 candidate = proposalIds[(_seed % length + i) % length];
                for (uint256 a; a < actors.length; ++a) {
                    if (multisig.canApprove(candidate, actors[a])) return candidate;
                }
            }
        }
        return proposalIds[_seed % length];
    }

    /// @dev Four times out of five, an executable proposal (if any).
    function _executableMostly(uint256 _seed) internal view returns (uint256) {
        uint256 length = proposalIds.length;
        if (_seed % 5 != 0) {
            for (uint256 i; i < length; ++i) {
                uint256 candidate = proposalIds[(_seed % length + i) % length];
                if (multisig.canExecute(candidate)) return candidate;
            }
        }
        return proposalIds[_seed % length];
    }

    function _buildActions(uint8 _count) internal view returns (Action[] memory actionList) {
        actionList = new Action[](_count);
        for (uint256 i; i < _count; ++i) {
            actionList[i] =
                Action({to: address(actionTarget), value: 0, data: abi.encodeCall(ActionTarget.setValue, (i + 1))});
        }
    }

    function _recordApproval(uint256 _proposalId, address _approver) internal {
        assertFalse(ghostApproved[_proposalId][_approver], "double approval");
        ghostApproved[_proposalId][_approver] = true;
        ghostApprovals[_proposalId]++;
    }

    /// @dev Approvals with `tryExecution` may execute; the executed flag going from false to true is an execution.
    function _syncExecution(uint256 _proposalId) internal {
        (bool executed,,,,,) = multisig.getProposal(_proposalId);
        if (executed && ghostExecutions[_proposalId] == 0) ghostExecutions[_proposalId] = 1;
    }
}
