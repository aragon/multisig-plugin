// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import {Multisig} from "../../../../../src/Multisig.sol";

contract UpdateMultisigSettings_Multisig_UnitTest is BaseTest {
    function test_RevertWhen_CallerHasNoPermission() external {
        // it should revert with DaoUnauthorized.
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(multisig),
                unauthorized,
                UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
            )
        );
        vm.prank(unauthorized);
        multisig.updateMultisigSettings(_settings(false, 1));
    }

    function test_WhenSettingsAreValid() external {
        // it should store the settings, record the block and emit MultisigSettingsUpdated.
        vm.roll(block.number + 7);

        vm.expectEmit(address(multisig));
        emit Multisig.MultisigSettingsUpdated(false, 3);
        _updateSettings(false, 3);

        (bool onlyListed, uint16 minApprovals) = multisig.multisigSettings();
        assertFalse(onlyListed, "onlyListed");
        assertEq(minApprovals, 3, "minApprovals");
        assertEq(multisig.lastMultisigSettingsChange(), block.number, "lastMultisigSettingsChange");
    }

    function test_WhenMinApprovalsIsOne() external {
        // it should accept the lower bound.
        _updateSettings(true, 1);
        (, uint16 minApprovals) = multisig.multisigSettings();
        assertEq(minApprovals, 1);
    }

    function test_WhenMinApprovalsEqualsTheMemberCount() external {
        // it should accept the upper bound.
        _updateSettings(true, 3);
        (, uint16 minApprovals) = multisig.multisigSettings();
        assertEq(minApprovals, 3);
    }

    function test_RevertWhen_MinApprovalsIsZero() external {
        // it should revert with MinApprovalsOutOfBounds(1, 0).
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 1, 0));
        _updateSettings(true, 0);
    }

    function test_RevertWhen_MinApprovalsExceedsTheMemberCount() external {
        // it should revert with MinApprovalsOutOfBounds(length, minApprovals).
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 3, 4));
        _updateSettings(true, 4);
    }

    function test_RevertWhen_MinApprovalsIsTheMaximum() external {
        // it should revert.
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 3, type(uint16).max));
        _updateSettings(true, type(uint16).max);
    }

    function test_WhenSettingsAreUnchanged() external {
        // it should still emit and bump lastMultisigSettingsChange.
        vm.roll(block.number + 3);
        vm.expectEmit(address(multisig));
        emit Multisig.MultisigSettingsUpdated(true, 2);
        _updateSettings(true, 2);
        assertEq(multisig.lastMultisigSettingsChange(), block.number);
    }

    function test_WhenMembersWereAddedInTheSameBlock() external {
        // it should validate against the updated length.
        _addMembers(_members(dave));
        _updateSettings(true, 4);
        (, uint16 minApprovals) = multisig.multisigSettings();
        assertEq(minApprovals, 4);
    }

    function test_WhenTogglingOnlyListed() external {
        // it should only change onlyListed.
        _updateSettings(false, 2);
        (bool onlyListed, uint16 minApprovals) = multisig.multisigSettings();
        assertFalse(onlyListed, "off");
        assertEq(minApprovals, 2, "minApprovals");

        _updateSettings(true, 2);
        (onlyListed,) = multisig.multisigSettings();
        assertTrue(onlyListed, "on");
    }
}
