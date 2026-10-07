// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {stdError} from "forge-std/StdError.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {IMembership} from "@aragon/osx-commons-contracts/src/plugin/extensions/membership/IMembership.sol";
import {Addresslist} from "@aragon/osx-commons-contracts/src/plugin/extensions/governance/Addresslist.sol";

import {Multisig} from "../../../../../src/Multisig.sol";

contract RemoveAddresses_Multisig_UnitTest is BaseTest {
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
        multisig.removeAddresses(_members(carol));
    }

    function test_WhenRemovingDownToExactlyMinApprovals() external {
        // it should unlist the member, decrease the length and emit MembersRemoved.
        vm.expectEmit(address(multisig));
        emit IMembership.MembersRemoved(_members(carol));
        _removeMembers(_members(carol));

        assertEq(multisig.addresslistLength(), 2, "length");
        assertFalse(multisig.isListed(carol), "listed");
        assertFalse(multisig.isMember(carol), "member");
    }

    function test_WhenRemoving_ItShouldNotChangeSettings() external {
        // it should not update lastMultisigSettingsChange (only updateMultisigSettings does).
        uint64 lastChange = multisig.lastMultisigSettingsChange();
        vm.roll(block.number + 10);
        _removeMembers(_members(carol));
        assertEq(multisig.lastMultisigSettingsChange(), lastChange);
    }

    function test_RevertWhen_RemovingBelowMinApprovals() external {
        // it should revert with MinApprovalsOutOfBounds(newLength, minApprovals).
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 1, 2));
        _removeMembers(_members(bob, carol));
    }

    function test_RevertWhen_RemovingEveryMember() external {
        // it should revert, minApprovals >= 1 keeps the list from becoming empty.
        _updateSettings(true, 1);
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 0, 1));
        _removeMembers(_members(alice, bob, carol));
    }

    function test_WhenLoweringMinApprovalsFirst() external {
        // it should allow shrinking below the previous threshold (order matters).
        _updateSettings(true, 1);
        _removeMembers(_members(bob, carol));
        assertEq(multisig.addresslistLength(), 1);
    }

    function test_RevertWhen_RemovingMoreEntriesThanMembers() external {
        // it should revert with an arithmetic panic instead of a custom error.
        // FINDING: F13. `addresslistLength() - _members.length` underflows before any validation.
        address[] memory list = new address[](4);
        list[0] = alice;
        list[1] = bob;
        list[2] = carol;
        list[3] = dave;
        vm.expectRevert(stdError.arithmeticError);
        _removeMembers(list);
    }

    function test_RevertWhen_AnAddressIsNotListed() external {
        // it should revert with InvalidAddresslistUpdate.
        vm.expectRevert(abi.encodeWithSelector(Addresslist.InvalidAddresslistUpdate.selector, dave));
        _removeMembers(_members(dave));
    }

    function test_RevertWhen_ANonMemberWouldBreakTheThreshold() external {
        // it should revert with MinApprovalsOutOfBounds, the length check counts entries, not members.
        _updateSettings(true, 3);
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 2, 3));
        _removeMembers(_members(dave));
    }

    function test_RevertWhen_TheListContainsDuplicates() external {
        // it should revert with InvalidAddresslistUpdate.
        _updateSettings(true, 1);
        vm.expectRevert(abi.encodeWithSelector(Addresslist.InvalidAddresslistUpdate.selector, carol));
        _removeMembers(_members(carol, carol));
    }

    function test_WhenTheListIsEmpty() external {
        // it should succeed, emit MembersRemoved with an empty list and keep the length.
        vm.expectEmit(address(multisig));
        emit IMembership.MembersRemoved(new address[](0));
        _removeMembers(new address[](0));
        assertEq(multisig.addresslistLength(), 3);
    }

    function test_WhenCheckingHistoricalMembership() external {
        // it should keep the removed member listed at earlier blocks.
        uint256 removeBlock = block.number;
        _removeMembers(_members(carol));
        vm.roll(removeBlock + 1);

        assertTrue(multisig.isListedAtBlock(carol, removeBlock - 1), "before");
        assertFalse(multisig.isListedAtBlock(carol, removeBlock), "at");
        assertEq(multisig.addresslistLengthAtBlock(removeBlock - 1), 3, "length before");
        assertEq(multisig.addresslistLengthAtBlock(removeBlock), 2, "length at");
    }
}
