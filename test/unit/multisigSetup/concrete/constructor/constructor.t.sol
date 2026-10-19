// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {MultisigSetupBaseTest} from "../../MultisigSetupBaseTest.t.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";

import {Multisig} from "../../../../../src/Multisig.sol";
import {MultisigSetup} from "../../../../../src/MultisigSetup.sol";

contract Constructor_MultisigSetup_UnitTest is MultisigSetupBaseTest {
    bytes4 internal constant IPLUGIN_SETUP_ID = bytes4(keccak256("prepareInstallation(address,bytes)"))
        ^ bytes4(keccak256("prepareUpdate(address,uint16,(address,address[],bytes))"))
        ^ bytes4(keccak256("prepareUninstallation(address,(address,address[],bytes))"))
        ^ bytes4(keccak256("implementation()"));

    function test_WhenDeployed() external view {
        // it should deploy a Multisig implementation with code.
        address impl = setup.implementation();
        assertTrue(impl != address(0), "implementation");
        assertGt(impl.code.length, 0, "code");
        assertTrue(Multisig(impl).supportsInterface(MULTISIG_ID), "is a Multisig");
    }

    function test_RevertWhen_InitializingTheImplementation() external {
        // it should revert, the implementation has its initializers disabled.
        Multisig impl = Multisig(setup.implementation());
        vm.expectRevert(PluginUUPSUpgradeable.AlreadyInitialized.selector);
        impl.initialize(IDAO(address(dao)), _members(alice), _settings(false, 1), _daoTarget(), PLUGIN_METADATA);

        vm.expectRevert("Initializable: contract is already initialized");
        impl.initializeFrom(1, abi.encode(_daoTarget(), PLUGIN_METADATA));
    }

    function test_WhenDeployedTwice() external {
        // it should deploy a distinct implementation each time.
        MultisigSetup other = new MultisigSetup();
        assertTrue(other.implementation() != setup.implementation());
    }

    function test_WhenCheckingInterfaces() external view {
        // it should support IPluginSetup, IProtocolVersion and IERC165 only.
        assertEq(type(IPluginSetup).interfaceId, IPLUGIN_SETUP_ID, "independent IPluginSetup id");
        assertTrue(setup.supportsInterface(IPLUGIN_SETUP_ID), "IPluginSetup");
        assertTrue(setup.supportsInterface(IPROTOCOL_VERSION_ID), "IProtocolVersion");
        assertTrue(setup.supportsInterface(IERC165_ID), "IERC165");
        assertFalse(setup.supportsInterface(0xffffffff), "0xffffffff");
        assertFalse(setup.supportsInterface(MULTISIG_ID), "not the plugin interface");
    }

    function test_WhenReadingTheProtocolVersion() external view {
        // it should report the OSx version it was built against (1.4.0).
        uint8[3] memory version = setup.protocolVersion();
        assertEq(version[0], 1);
        assertEq(version[1], 4);
        assertEq(version[2], 0);
    }
}
