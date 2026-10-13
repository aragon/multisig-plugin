// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {Multisig} from "../../../../../src/Multisig.sol";

contract SupportsInterface_Multisig_UnitTest is BaseTest {
    function test_WhenQueryingTheErc165Id() external view {
        // it should return true.
        assertTrue(multisig.supportsInterface(IERC165_ID));
    }

    function test_WhenQueryingThePluginBaseIds() external view {
        // it should support IPlugin, IProtocolVersion, IERC1822 and the target config functions.
        assertTrue(multisig.supportsInterface(IPLUGIN_ID), "IPlugin");
        assertTrue(multisig.supportsInterface(IPROTOCOL_VERSION_ID), "IProtocolVersion");
        assertTrue(multisig.supportsInterface(IERC1822_ID), "IERC1822");
        assertTrue(multisig.supportsInterface(TARGET_CONFIG_ID), "targetConfig");
    }

    function test_WhenQueryingTheMetadataExtensionId() external view {
        // it should return true.
        assertTrue(multisig.supportsInterface(METADATA_EXTENSION_ID));
    }

    function test_WhenQueryingTheMembershipIds() external view {
        // it should support IMembership and Addresslist.
        assertTrue(multisig.supportsInterface(IMEMBERSHIP_ID), "IMembership");
        assertTrue(multisig.supportsInterface(ADDRESSLIST_ID), "Addresslist");
    }

    function test_WhenQueryingTheProposalIds() external view {
        // it should support the current IProposal ID.
        // it should support the legacy (OSx v1.0) IProposal ID, made of proposalCount() only.
        // it should not support the current ID minus proposalCount().
        assertTrue(multisig.supportsInterface(IPROPOSAL_ID), "IProposal");
        assertTrue(multisig.supportsInterface(IPROPOSAL_LEGACY_ID), "legacy IProposal");
        assertFalse(multisig.supportsInterface(IPROPOSAL_ID ^ IPROPOSAL_LEGACY_ID), "IProposal without proposalCount");
    }

    function test_WhenQueryingTheMultisigIds() external view {
        // it should support IMultisig and the custom Multisig ID.
        assertTrue(multisig.supportsInterface(IMULTISIG_ID), "IMultisig");
        assertTrue(multisig.supportsInterface(MULTISIG_ID), "Multisig");
    }

    function test_WhenQueryingTheImplementation() external {
        // it should give the same answers as the proxy (pure function of the code).
        Multisig implementation = new Multisig();
        assertTrue(implementation.supportsInterface(MULTISIG_ID), "Multisig");
        assertTrue(implementation.supportsInterface(IMULTISIG_ID), "IMultisig");
        assertFalse(implementation.supportsInterface(0xffffffff), "invalid");
    }

    function test_WhenQueryingTheInvalidId() external view {
        // it should return false (ERC-165 requirement).
        assertFalse(multisig.supportsInterface(0xffffffff));
    }

    function test_WhenQueryingUnrelatedIds() external view {
        // it should return false.
        assertFalse(multisig.supportsInterface(0x00000000), "zero");
        assertFalse(multisig.supportsInterface(bytes4(keccak256("random()"))), "random");
        // A single selector of a supported multi-function interface is not an interface ID by itself.
        assertFalse(multisig.supportsInterface(bytes4(keccak256("approve(uint256,bool)"))), "partial IMultisig");
        assertFalse(multisig.supportsInterface(bytes4(keccak256("getProposal(uint256)"))), "partial Multisig");
    }
}
