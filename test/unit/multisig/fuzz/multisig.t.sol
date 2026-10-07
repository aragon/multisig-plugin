// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../BaseTest.t.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {Addresslist} from "@aragon/osx-commons-contracts/src/plugin/extensions/governance/Addresslist.sol";
import {Action, IExecutor} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import {Multisig} from "../../../../src/Multisig.sol";
import {ListedCheckCondition} from "../../../../src/ListedCheckCondition.sol";
import {ActionTarget} from "../../../utils/mocks/ActionTarget.sol";

contract Multisig_FuzzTest is BaseTest {
    // ==== Member set sizes and minApprovals ====

    function testFuzz_InitializeAcceptsOnlyMinApprovalsWithinBounds(uint16 _memberCount, uint16 _minApprovals)
        external
    {
        // it should accept iff 1 <= minApprovals <= memberCount, and revert with the exact bound otherwise.
        _memberCount = uint16(bound(_memberCount, 0, 40));
        address impl = address(new Multisig());
        bytes memory data = abi.encodeCall(
            Multisig.initialize,
            (
                IDAO(address(dao)),
                _generatedMembers(_memberCount, 0),
                _settings(false, _minApprovals),
                _daoTarget(),
                PLUGIN_METADATA
            )
        );

        if (_minApprovals > _memberCount) {
            vm.expectRevert(
                abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, _memberCount, _minApprovals)
            );
        } else if (_minApprovals == 0) {
            vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 1, 0));
        }
        Multisig plugin = Multisig(address(new ERC1967Proxy(impl, data)));

        if (_minApprovals != 0 && _minApprovals <= _memberCount) {
            (, uint16 stored) = plugin.multisigSettings();
            assertEq(stored, _minApprovals, "minApprovals");
            assertEq(plugin.addresslistLength(), _memberCount, "length");
        }
    }

    function testFuzz_UpdateSettingsAcceptsOnlyMinApprovalsWithinBounds(bool _onlyListed, uint16 _minApprovals)
        external
    {
        // it should accept iff 1 <= minApprovals <= 3 (the member count) and leave settings untouched otherwise.
        if (_minApprovals > 3) {
            vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 3, _minApprovals));
        } else if (_minApprovals == 0) {
            vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 1, 0));
        }
        _updateSettings(_onlyListed, _minApprovals);

        (bool onlyListed, uint16 minApprovals) = multisig.multisigSettings();
        if (_minApprovals != 0 && _minApprovals <= 3) {
            assertEq(onlyListed, _onlyListed, "onlyListed");
            assertEq(minApprovals, _minApprovals, "minApprovals");
            assertEq(multisig.lastMultisigSettingsChange(), block.number, "lastChange");
        } else {
            assertTrue(onlyListed, "onlyListed unchanged");
            assertEq(minApprovals, 2, "minApprovals unchanged");
        }
    }

    function testFuzz_RemoveAddressesKeepsAtLeastMinApprovalsMembers(uint8 _removeCount, uint16 _minApprovals)
        external
    {
        // it should allow removals iff the remaining member count stays >= minApprovals.
        _removeCount = uint8(bound(_removeCount, 0, 3));
        _minApprovals = uint16(bound(_minApprovals, 1, 3));
        _updateSettings(true, _minApprovals);

        address[] memory all = _members(alice, bob, carol);
        address[] memory toRemove = new address[](_removeCount);
        for (uint256 i; i < _removeCount; ++i) {
            toRemove[i] = all[i];
        }
        uint16 remaining = uint16(3 - _removeCount);

        if (remaining < _minApprovals) {
            vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, remaining, _minApprovals));
        }
        _removeMembers(toRemove);

        if (remaining >= _minApprovals) {
            assertEq(multisig.addresslistLength(), remaining, "length");
            for (uint256 i; i < 3; ++i) {
                assertEq(multisig.isListed(all[i]), i >= _removeCount, "listed");
            }
        } else {
            assertEq(multisig.addresslistLength(), 3, "length unchanged");
        }
    }

    function testFuzz_AddAddressesRejectsAlreadyListedMembers(uint256 _existing, uint256 _added, uint256 _offset)
        external
    {
        // it should revert on the first already listed address, and otherwise grow the list exactly.
        _existing = bound(_existing, 1, 20);
        _added = bound(_added, 0, 20);
        _offset = bound(_offset, 0, 40);
        multisig = _deployMultisig(dao, _generatedMembers(_existing, 0), _settings(false, 1), _daoTarget(), "");
        _grantSetupPermissions(multisig, address(new ListedCheckCondition(address(multisig))));

        address[] memory toAdd = _generatedMembers(_added, _offset);
        bool overlaps = _added > 0 && _offset < _existing;
        if (overlaps) {
            vm.expectRevert(abi.encodeWithSelector(Addresslist.InvalidAddresslistUpdate.selector, toAdd[0]));
        }
        _addMembers(toAdd);

        assertEq(multisig.addresslistLength(), overlaps ? _existing : _existing + _added, "length");
    }

    // ==== Proposal dates ====

    function testFuzz_CreateProposalAcceptsOnlyValidDates(uint64 _startDate, uint64 _endDate) external {
        // it should accept iff (start == 0 or start >= now) and end >= effective start, with exact revert args.
        uint64 nowTs = uint64(block.timestamp);
        uint64 effectiveStart = _startDate == 0 ? nowTs : _startDate;

        if (_startDate != 0 && _startDate < nowTs) {
            vm.expectRevert(abi.encodeWithSelector(Multisig.DateOutOfBounds.selector, nowTs, _startDate));
        } else if (_endDate < effectiveStart) {
            vm.expectRevert(abi.encodeWithSelector(Multisig.DateOutOfBounds.selector, effectiveStart, _endDate));
        }
        vm.prank(alice);
        uint256 proposalId =
            multisig.createProposal(PROPOSAL_METADATA, _actions(1), 0, false, false, _startDate, _endDate);

        if ((_startDate == 0 || _startDate >= nowTs) && _endDate >= effectiveStart) {
            (,, Multisig.ProposalParameters memory parameters,,,) = multisig.getProposal(proposalId);
            assertEq(parameters.startDate, effectiveStart, "startDate");
            assertEq(parameters.endDate, _endDate, "endDate");
            assertEq(parameters.snapshotBlock, block.number - 1, "snapshotBlock");
            assertEq(parameters.minApprovals, 2, "minApprovals");
        }
    }

    function testFuzz_CanApproveOnlyWithinTheWindow(uint64 _startOffset, uint64 _duration, uint64 _warpTo) external {
        // it should allow approving iff startDate <= now <= endDate.
        _startOffset = uint64(bound(_startOffset, 0, 365 days));
        _duration = uint64(bound(_duration, 0, 365 days));
        uint64 start = uint64(block.timestamp) + _startOffset;
        uint64 end = start + _duration;

        vm.prank(alice);
        uint256 proposalId = multisig.createProposal(PROPOSAL_METADATA, _actions(1), 0, false, false, start, end);

        _warpTo = uint64(bound(_warpTo, block.timestamp, uint256(end) + 365 days));
        vm.warp(_warpTo);
        bool open = _warpTo >= start && _warpTo <= end;

        assertEq(multisig.canApprove(proposalId, bob), open, "canApprove");
        if (!open) {
            vm.expectRevert(abi.encodeWithSelector(Multisig.ApprovalCastForbidden.selector, proposalId, bob));
        }
        _approve(proposalId, bob);
        assertEq(multisig.hasApproved(proposalId, bob), open, "hasApproved");
    }

    // ==== allowFailureMap ====

    function testFuzz_ExecutionSucceedsIffEveryFailingActionIsAllowed(
        uint8 _actionCount,
        uint256 _failingMask,
        uint256 _allowFailureMap
    ) external {
        // it should execute iff every failing action has its bit set in allowFailureMap,
        // and the DAO reports exactly the failing actions in failureMap.
        _actionCount = uint8(bound(_actionCount, 1, 8));
        _failingMask &= (uint256(1) << _actionCount) - 1;

        Action[] memory actionList = new Action[](_actionCount);
        bytes[] memory expectedResults = new bytes[](_actionCount);
        uint256 firstForbiddenFailure = type(uint256).max;
        for (uint256 i; i < _actionCount; ++i) {
            if (_failingMask & (uint256(1) << i) != 0) {
                actionList[i] = _failingAction();
                expectedResults[i] = abi.encodeWithSelector(ActionTarget.ActionReverted.selector);
                if (_allowFailureMap & (uint256(1) << i) == 0 && firstForbiddenFailure == type(uint256).max) {
                    firstForbiddenFailure = i;
                }
            } else {
                actionList[i] =
                    Action({to: address(actionTarget), value: 0, data: abi.encodeCall(ActionTarget.setValue, (i + 1))});
            }
        }

        uint256 proposalId = _createProposal(alice, actionList, _allowFailureMap, true, false);
        _approve(proposalId, bob);
        assertTrue(multisig.canExecute(proposalId), "canExecute");

        if (firstForbiddenFailure != type(uint256).max) {
            vm.expectRevert(abi.encodeWithSelector(DAO.ActionFailed.selector, firstForbiddenFailure));
            vm.prank(carol);
            multisig.execute(proposalId);

            (bool executed,,,,,) = multisig.getProposal(proposalId);
            assertFalse(executed, "not executed");
            assertTrue(multisig.canExecute(proposalId), "still executable");
            return;
        }

        vm.expectEmit(address(dao));
        emit IExecutor.Executed(
            address(multisig), bytes32(proposalId), actionList, _allowFailureMap, _failingMask, expectedResults
        );
        vm.prank(carol);
        multisig.execute(proposalId);

        (bool done,,,,,) = multisig.getProposal(proposalId);
        assertTrue(done, "executed");
    }

    // ==== Approval orderings ====

    function testFuzz_ExecutableExactlyWhenApprovalsReachMinApprovals(
        uint8 _memberCount,
        uint8 _minApprovals,
        uint256 _seed
    ) external {
        // it should report canExecute and hasSucceeded true exactly from the M-th approval on,
        // whatever the approval order.
        _memberCount = uint8(bound(_memberCount, 1, 20));
        _minApprovals = uint8(bound(_minApprovals, 1, _memberCount));
        address[] memory memberList = _generatedMembers(_memberCount, 0);

        multisig = _deployMultisig(dao, memberList, _settings(true, _minApprovals), _daoTarget(), "");
        _grantSetupPermissions(multisig, address(new ListedCheckCondition(address(multisig))));
        vm.roll(block.number + 1);

        uint256 proposalId = _createProposal(memberList[0]);

        // Fisher-Yates shuffle driven by the seed.
        for (uint256 i = memberList.length; i > 1; --i) {
            uint256 j = uint256(keccak256(abi.encode(_seed, i))) % i;
            (memberList[i - 1], memberList[j]) = (memberList[j], memberList[i - 1]);
        }

        for (uint256 k; k < memberList.length; ++k) {
            assertEq(multisig.canExecute(proposalId), k >= _minApprovals, "canExecute before");
            assertEq(multisig.hasSucceeded(proposalId), k >= _minApprovals, "hasSucceeded before");
            assertTrue(multisig.canApprove(proposalId, memberList[k]), "canApprove");
            _approve(proposalId, memberList[k]);
            assertFalse(multisig.canApprove(proposalId, memberList[k]), "cannot approve twice");
            (, uint16 approvals,,,,) = multisig.getProposal(proposalId);
            assertEq(approvals, k + 1, "approvals");
        }
        assertTrue(multisig.canExecute(proposalId), "canExecute after all");

        vm.prank(unauthorized);
        multisig.execute(proposalId);
        assertEq(actionTarget.value(), 1, "executed");
        assertFalse(multisig.canExecute(proposalId), "not executable twice");
        assertTrue(multisig.hasSucceeded(proposalId), "hasSucceeded stays true");
    }

    // ==== Proposal IDs ====

    function testFuzz_ProposalIdsAreUniquePerContentAndBlock(
        bytes memory _metadataA,
        bytes memory _metadataB,
        uint256 _valueA,
        uint256 _valueB,
        uint8 _blockGap
    ) external {
        // it should derive the ID from (chainid, block, plugin, actions, metadata) only.
        Action[] memory actionsA = _singleAction(_valueA);
        Action[] memory actionsB = _singleAction(_valueB);
        uint64 end = uint64(block.timestamp) + PROPOSAL_DURATION;

        vm.prank(alice);
        uint256 idA = multisig.createProposal(_metadataA, actionsA, 0, false, false, 0, end);
        assertEq(idA, _expectedProposalId(actionsA, _metadataA), "idA formula");

        bool sameContent = _valueA == _valueB && keccak256(_metadataA) == keccak256(_metadataB);
        if (sameContent) {
            vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalAlreadyExists.selector, idA));
        }
        vm.prank(bob);
        uint256 idB = multisig.createProposal(_metadataB, actionsB, 0, false, false, 0, end);
        if (!sameContent) {
            assertTrue(idA != idB, "different content, different id");
        }

        // Same content in a later block always yields a fresh ID.
        vm.roll(block.number + 1 + uint256(_blockGap));
        vm.prank(alice);
        uint256 idC = multisig.createProposal(_metadataA, actionsA, 0, false, false, 0, end);
        assertTrue(idC != idA, "later block, different id");
        assertEq(idC, _expectedProposalId(actionsA, _metadataA), "idC formula");
    }

    function testFuzz_ProposalIdIgnoresFailureMapDatesAndCreator(
        uint256 _allowFailureMap,
        uint64 _endOffset,
        bool _creatorIsBob
    ) external {
        // it should collide on identical actions and metadata in the same block, whatever the other
        // parameters (front-running vector, finding F3).
        _endOffset = uint64(bound(_endOffset, 0, 365 days));
        uint256 idA = _createProposal(alice);

        vm.expectRevert(abi.encodeWithSelector(Multisig.ProposalAlreadyExists.selector, idA));
        vm.prank(_creatorIsBob ? bob : carol);
        multisig.createProposal(
            PROPOSAL_METADATA, _actions(1), _allowFailureMap, false, false, 0, uint64(block.timestamp) + _endOffset
        );
    }

    function _singleAction(uint256 _value) internal view returns (Action[] memory actionList) {
        actionList = new Action[](1);
        actionList[0] =
            Action({to: address(actionTarget), value: 0, data: abi.encodeCall(ActionTarget.setValue, (_value))});
    }
}
