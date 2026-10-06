// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import {Multisig} from "../../src/Multisig.sol";
import {ActionTarget} from "../utils/mocks/ActionTarget.sol";
import {ForkBaseTest} from "./ForkBaseTest.t.sol";

/// @dev A DAO created through the live DAOFactory with this repository's Multisig.
contract Installation_ForkTest is ForkBaseTest {
    DAO internal dao;
    Multisig internal multisig;

    function setUp() public override {
        super.setUp();
        address plugin;
        (dao, plugin) = _createDao(localTag, _installData(_members(), 2));
        multisig = Multisig(plugin);
        vm.roll(block.number + 1);
    }

    function test_WhenInstalledThroughTheDaoFactory() external view {
        // it should run this repository's implementation, initialized for the new DAO.
        assertEq(multisig.implementation(), localSetup.implementation(), "implementation");
        assertEq(address(multisig.dao()), address(dao), "dao");
        assertEq(multisig.addresslistLength(), 3, "members");
        (bool onlyListed, uint16 minApprovals) = multisig.multisigSettings();
        assertTrue(onlyListed, "onlyListed");
        assertEq(minApprovals, 2, "minApprovals");
        assertEq(multisig.getMetadata(), bytes("ipfs://fork-plugin-metadata"), "metadata");
        assertEq(multisig.getTargetConfig().target, address(dao), "effective target");
    }

    function test_WhenInstalled_ItShouldHoldExactlyTheSetupPermissions() external view {
        // it should grant what MultisigSetup prepares, and nothing that build 3 removed.
        address m = address(multisig);
        assertTrue(dao.hasPermission(address(dao), m, EXECUTE_PERMISSION_ID, ""), "EXECUTE on DAO");
        assertTrue(dao.hasPermission(m, address(dao), UPDATE_MULTISIG_SETTINGS_PERMISSION_ID, ""), "settings");
        assertTrue(dao.hasPermission(m, address(dao), SET_TARGET_CONFIG_PERMISSION_ID, ""), "target config");
        assertTrue(dao.hasPermission(m, address(dao), SET_METADATA_PERMISSION_ID, ""), "metadata");
        assertTrue(dao.hasPermission(m, carol, EXECUTE_PROPOSAL_PERMISSION_ID, ""), "execute proposal: anyone");
        assertTrue(dao.hasPermission(m, alice, CREATE_PROPOSAL_PERMISSION_ID, ""), "create: member");
        assertFalse(dao.hasPermission(m, address(0xBEEF), CREATE_PROPOSAL_PERMISSION_ID, ""), "create: outsider");
        assertFalse(dao.hasPermission(m, address(dao), UPGRADE_PLUGIN_PERMISSION_ID, ""), "no upgrade permission");
        assertFalse(dao.hasPermission(address(dao), address(psp), ROOT_PERMISSION_ID, ""), "PSP has no ROOT");
    }

    function test_WhenAProposalPasses() external {
        // it should execute its actions through the DAO.
        Action[] memory actions = new Action[](1);
        actions[0] = Action({to: address(actionTarget), value: 0, data: abi.encodeCall(ActionTarget.setValue, (42))});

        vm.prank(alice);
        uint256 id = multisig.createProposal("ipfs://p", actions, 0, true, false, 0, uint64(block.timestamp + 1 days));
        vm.prank(bob);
        multisig.approve(id, true);

        (bool executed,,,,,) = multisig.getProposal(id);
        assertTrue(executed, "executed");
        assertEq(actionTarget.value(), 42, "action ran");
        assertEq(actionTarget.lastCaller(), address(dao), "through the DAO");
    }
}
