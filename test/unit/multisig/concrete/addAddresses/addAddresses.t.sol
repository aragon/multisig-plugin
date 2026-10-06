// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {IMembership} from "@aragon/osx-commons-contracts/src/plugin/extensions/membership/IMembership.sol";
import {Addresslist} from "@aragon/osx-commons-contracts/src/plugin/extensions/governance/Addresslist.sol";

import {Multisig} from "../../../../../src/Multisig.sol";

contract AddAddresses_Multisig_UnitTest is BaseTest {
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
        multisig.addAddresses(_members(dave));
    }

    function test_RevertWhen_CallerIsAMember() external {
        // it should revert, being a member grants no management rights.
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(multisig), alice, UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
            )
        );
        vm.prank(alice);
        multisig.addAddresses(_members(dave));
    }

    function test_WhenAddingNewMembers() external {
        // it should list them, increase the length and emit MembersAdded.
        address[] memory newMembers = _members(dave, unauthorized);

        vm.expectEmit(address(multisig));
        emit IMembership.MembersAdded(newMembers);
        _addMembers(newMembers);

        assertEq(multisig.addresslistLength(), 5, "length");
        assertTrue(multisig.isListed(dave) && multisig.isMember(dave), "dave");
        assertTrue(multisig.isListed(unauthorized) && multisig.isMember(unauthorized), "unauthorized");
    }

    function test_WhenAddingNewMembers_ItShouldNotChangeSettings() external {
        // it should keep minApprovals and onlyListed.
        // it should not update lastMultisigSettingsChange (only updateMultisigSettings does).
        uint64 lastChange = multisig.lastMultisigSettingsChange();
        vm.roll(block.number + 10);

        _addMembers(_members(dave));

        (bool onlyListed, uint16 minApprovals) = multisig.multisigSettings();
        assertTrue(onlyListed, "onlyListed");
        assertEq(minApprovals, 2, "minApprovals");
        assertEq(multisig.lastMultisigSettingsChange(), lastChange, "lastMultisigSettingsChange");
    }

    function test_WhenTheListIsEmpty() external {
        // it should succeed, emit MembersAdded with an empty list and keep the length.
        vm.expectEmit(address(multisig));
        emit IMembership.MembersAdded(new address[](0));
        _addMembers(new address[](0));
        assertEq(multisig.addresslistLength(), 3);
    }

    function test_RevertWhen_AnAddressIsAlreadyListed() external {
        // it should revert with InvalidAddresslistUpdate and add nothing.
        vm.expectRevert(abi.encodeWithSelector(Addresslist.InvalidAddresslistUpdate.selector, alice));
        _addMembers(_members(dave, alice));
        assertFalse(multisig.isListed(dave), "dave not added");
    }

    function test_RevertWhen_TheListContainsDuplicates() external {
        // it should revert with InvalidAddresslistUpdate.
        vm.expectRevert(abi.encodeWithSelector(Addresslist.InvalidAddresslistUpdate.selector, dave));
        _addMembers(_members(dave, dave));
    }

    function test_WhenReachingExactlyTheMaximumLength() external {
        // it should accept type(uint16).max members in total.
        _addMembers(_generatedMembers(uint256(type(uint16).max) - 3, 0));
        assertEq(multisig.addresslistLength(), type(uint16).max);
    }

    function test_RevertWhen_ExceedingTheMaximumLength() external {
        // it should revert with AddresslistLengthOutOfBounds, counting the existing members.
        _addMembers(_generatedMembers(uint256(type(uint16).max) - 3, 0));

        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.AddresslistLengthOutOfBounds.selector, type(uint16).max, uint256(type(uint16).max) + 1
            )
        );
        _addMembers(_members(dave));
    }

    function test_RevertWhen_ExceedingTheMaximumLengthInOneCall() external {
        // it should revert before touching the list.
        address[] memory tooMany = _generatedMembers(uint256(type(uint16).max) - 2, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.AddresslistLengthOutOfBounds.selector, type(uint16).max, uint256(type(uint16).max) + 1
            )
        );
        _addMembers(tooMany);
    }

    function test_WhenAddingTheZeroAddress() external {
        // it should accept it and count it as a member.
        // FINDING: F8. No member validation: address(0) counts towards the length, so minApprovals can be
        // raised to a value that no set of real signers can ever reach.
        _addMembers(_members(address(0)));
        assertTrue(multisig.isListed(address(0)), "listed");
        assertEq(multisig.addresslistLength(), 4, "length");

        _updateSettings(true, 4);
        vm.roll(block.number + 1);

        uint256 proposalId = _createProposal(alice, _actions(1), 0, true, false);
        _approve(proposalId, bob);
        _approve(proposalId, carol);

        assertFalse(multisig.canExecute(proposalId), "unreachable threshold");
    }

    function test_WhenAddingThePluginOrTheDao() external {
        // it should accept them (no validation).
        _addMembers(_members(address(multisig), address(dao)));
        assertTrue(multisig.isListed(address(multisig)), "plugin");
        assertTrue(multisig.isListed(address(dao)), "dao");
    }

    function test_WhenCheckingHistoricalMembership() external {
        // it should not list a member before the block it was added in.
        // it should report the length per block.
        uint256 addBlock = block.number;
        _addMembers(_members(dave));
        vm.roll(addBlock + 1);

        assertFalse(multisig.isListedAtBlock(dave, addBlock - 1), "before");
        assertTrue(multisig.isListedAtBlock(dave, addBlock), "at");
        assertEq(multisig.addresslistLengthAtBlock(addBlock - 1), 3, "length before");
        assertEq(multisig.addresslistLengthAtBlock(addBlock), 4, "length at");
    }

    function test_RevertWhen_QueryingTheCurrentBlock() external {
        // it should revert, checkpoints are only readable for mined blocks.
        vm.expectRevert("Checkpoints: block not yet mined");
        multisig.isListedAtBlock(alice, block.number);
    }

    function test_WhenAddingAndRemovingInTheSameBlock() external {
        // it should keep a single checkpoint per block with the final state.
        uint256 currentBlock = block.number;
        _addMembers(_members(dave));
        _removeMembers(_members(dave));
        vm.roll(currentBlock + 1);

        assertFalse(multisig.isListed(dave), "current");
        assertFalse(multisig.isListedAtBlock(dave, currentBlock), "at block");
        assertEq(multisig.addresslistLengthAtBlock(currentBlock), 3, "length");
    }

    function test_WhenReAddingARemovedMember() external {
        // it should list it again and keep the history.
        uint256 removeBlock = block.number;
        _removeMembers(_members(carol));
        vm.roll(removeBlock + 5);
        _addMembers(_members(carol));
        vm.roll(removeBlock + 6);

        assertTrue(multisig.isListedAtBlock(carol, removeBlock - 1), "before removal");
        assertFalse(multisig.isListedAtBlock(carol, removeBlock), "removed");
        assertTrue(multisig.isListedAtBlock(carol, removeBlock + 5), "re-added");
        assertEq(multisig.addresslistLength(), 3, "length");
    }
}
