// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {
    ProposalUpgradeable
} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/ProposalUpgradeable.sol";

import {Multisig} from "../../../../../src/Multisig.sol";

contract Views_Multisig_UnitTest is BaseTest {
    function test_WhenCheckingIsMember() external {
        // it should mirror the current address list.
        assertTrue(multisig.isMember(alice), "alice");
        assertFalse(multisig.isMember(dave), "dave");

        _addMembers(_members(dave));
        assertTrue(multisig.isMember(dave), "dave added");

        _removeMembers(_members(carol));
        assertFalse(multisig.isMember(carol), "carol removed");
    }

    function test_WhenReadingCustomProposalParamsABI() external view {
        // it should describe the `_data` decoded by the IProposal createProposal overload.
        assertEq(
            multisig.customProposalParamsABI(), "(uint256 allowFailureMap, bool approveProposal, bool tryExecution)"
        );
    }

    function test_RevertWhen_ReadingProposalCount() external {
        // it should revert with FunctionDeprecated.
        // FINDING: F14. Integrations reading proposalCount() break after upgrading to build 3.
        vm.expectRevert(ProposalUpgradeable.FunctionDeprecated.selector);
        multisig.proposalCount();
    }

    function test_WhenReadingTheProtocolVersion() external view {
        // it should return the OSx protocol version the plugin was built against.
        uint8[3] memory version = multisig.protocolVersion();
        assertEq(version[0], 1, "major");
        assertEq(version[1], 4, "minor");
        assertEq(version[2], 0, "patch");
    }

    function test_WhenReadingThePluginType() external view {
        // it should return UUPS.
        assertEq(uint8(multisig.pluginType()), uint8(IPlugin.PluginType.UUPS));
    }

    function test_WhenReadingTheImplementation() external view {
        // it should return the address stored in the ERC-1967 slot.
        address fromSlot = address(uint160(uint256(vm.load(address(multisig), IMPLEMENTATION_SLOT))));
        assertNotEq(fromSlot, address(0), "slot set");
        assertEq(multisig.implementation(), fromSlot, "implementation");
    }

    function test_WhenReadingTheDao() external view {
        // it should return the DAO given at initialization.
        assertEq(address(multisig.dao()), address(dao));
    }

    function test_WhenReadingThePermissionIds() external view {
        // it should match the documented permission identifiers.
        assertEq(multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID(), UPDATE_MULTISIG_SETTINGS_PERMISSION_ID, "update");
        assertEq(multisig.CREATE_PROPOSAL_PERMISSION_ID(), CREATE_PROPOSAL_PERMISSION_ID, "create");
        assertEq(multisig.EXECUTE_PROPOSAL_PERMISSION_ID(), EXECUTE_PROPOSAL_PERMISSION_ID, "execute");
        assertEq(multisig.SET_TARGET_CONFIG_PERMISSION_ID(), SET_TARGET_CONFIG_PERMISSION_ID, "target");
        assertEq(multisig.SET_METADATA_PERMISSION_ID(), SET_METADATA_PERMISSION_ID, "metadata");
        assertEq(multisig.UPGRADE_PLUGIN_PERMISSION_ID(), UPGRADE_PLUGIN_PERMISSION_ID, "upgrade");
    }
}
