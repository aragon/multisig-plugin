// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IMembership} from "@aragon/osx-commons-contracts/src/plugin/extensions/membership/IMembership.sol";
import {Addresslist} from "@aragon/osx-commons-contracts/src/plugin/extensions/governance/Addresslist.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";
import {
    MetadataExtensionUpgradeable
} from "@aragon/osx-commons-contracts/src/utils/metadata/MetadataExtensionUpgradeable.sol";

import {Multisig} from "../../../../../src/Multisig.sol";
import {CustomExecutorMock} from "../../../../utils/mocks/CustomExecutorMock.sol";

contract Initialize_Multisig_UnitTest is BaseTest {
    Multisig internal implementation;

    function setUp() public override {
        super.setUp();
        implementation = new Multisig();
    }

    function _initData(address[] memory _memberList, uint16 _minApprovals) internal view returns (bytes memory) {
        return abi.encodeCall(
            Multisig.initialize,
            (IDAO(address(dao)), _memberList, _settings(false, _minApprovals), _daoTarget(), PLUGIN_METADATA)
        );
    }

    function test_RevertWhen_CalledOnTheImplementation() external {
        // it should revert, the constructor disables initializers.
        vm.expectRevert(PluginUUPSUpgradeable.AlreadyInitialized.selector);
        implementation.initialize(
            IDAO(address(dao)), _members(alice), _settings(false, 1), _daoTarget(), PLUGIN_METADATA
        );
    }

    function test_RevertWhen_CalledTwice() external {
        // it should revert.
        vm.expectRevert(PluginUUPSUpgradeable.AlreadyInitialized.selector);
        multisig.initialize(IDAO(address(dao)), _members(dave), _settings(false, 1), _daoTarget(), PLUGIN_METADATA);
    }

    function test_WhenInitializedWithValidData() external {
        // it should store the DAO, members, settings, target config and metadata.
        address[] memory memberList = _members(alice, bob, carol);
        IPlugin.TargetConfig memory target =
            IPlugin.TargetConfig({target: address(new CustomExecutorMock()), operation: IPlugin.Operation.Call});

        Multisig plugin = _deployMultisig(dao, memberList, _settings(false, 3), target, PLUGIN_METADATA);

        assertEq(address(plugin.dao()), address(dao), "dao");
        assertEq(plugin.addresslistLength(), 3, "length");
        for (uint256 i; i < memberList.length; ++i) {
            assertTrue(plugin.isListed(memberList[i]), "listed");
            assertTrue(plugin.isMember(memberList[i]), "member");
        }
        (bool onlyListed, uint16 minApprovals) = plugin.multisigSettings();
        assertFalse(onlyListed, "onlyListed");
        assertEq(minApprovals, 3, "minApprovals");
        assertEq(plugin.lastMultisigSettingsChange(), block.number, "lastMultisigSettingsChange");
        assertEq(plugin.getCurrentTargetConfig().target, target.target, "target");
        assertEq(uint8(plugin.getCurrentTargetConfig().operation), uint8(target.operation), "operation");
        assertEq(plugin.getMetadata(), PLUGIN_METADATA, "metadata");
    }

    function test_WhenInitialized_ItShouldEmitAllEvents() external {
        // it should emit MembersAdded, MultisigSettingsUpdated, MetadataSet and TargetSet, in that order.
        address[] memory memberList = _members(alice, bob);
        address proxyAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        Multisig impl = new Multisig();
        assertEq(proxyAddress, vm.computeCreateAddress(address(this), vm.getNonce(address(this))), "precomputed");

        vm.expectEmit(proxyAddress);
        emit IMembership.MembersAdded(memberList);
        vm.expectEmit(proxyAddress);
        emit Multisig.MultisigSettingsUpdated(true, 2);
        vm.expectEmit(proxyAddress);
        emit MetadataExtensionUpgradeable.MetadataSet(PLUGIN_METADATA);
        vm.expectEmit(proxyAddress);
        emit PluginUUPSUpgradeable.TargetSet(_daoTarget());

        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(
                Multisig.initialize, (IDAO(address(dao)), memberList, _settings(true, 2), _daoTarget(), PLUGIN_METADATA)
            )
        );
    }

    function test_RevertWhen_MembersAreEmpty() external {
        // it should revert, minApprovals cannot exceed zero members.
        address impl = address(implementation);
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 0, 1));
        new ERC1967Proxy(impl, _initData(new address[](0), 1));
    }

    function test_RevertWhen_MinApprovalsIsZero() external {
        // it should revert.
        address impl = address(implementation);
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 1, 0));
        new ERC1967Proxy(impl, _initData(_members(alice), 0));
    }

    function test_RevertWhen_MinApprovalsExceedsMembers() external {
        // it should revert.
        address impl = address(implementation);
        vm.expectRevert(abi.encodeWithSelector(Multisig.MinApprovalsOutOfBounds.selector, 2, 3));
        new ERC1967Proxy(impl, _initData(_members(alice, bob), 3));
    }

    function test_RevertWhen_MembersContainDuplicates() external {
        // it should revert.
        address impl = address(implementation);
        vm.expectRevert(abi.encodeWithSelector(Addresslist.InvalidAddresslistUpdate.selector, alice));
        new ERC1967Proxy(impl, _initData(_members(alice, alice), 1));
    }

    function test_WhenMembersAreExactlyTheMaximum() external {
        // it should accept type(uint16).max members.
        Multisig plugin = _deployMultisig(
            dao, _generatedMembers(type(uint16).max, 0), _settings(false, 1), _daoTarget(), PLUGIN_METADATA
        );
        assertEq(plugin.addresslistLength(), type(uint16).max);
    }

    function test_RevertWhen_MembersExceedTheMaximum() external {
        // it should revert.
        address impl = address(implementation);
        bytes memory data = _initData(_generatedMembers(uint256(type(uint16).max) + 1, 0), 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.AddresslistLengthOutOfBounds.selector, type(uint16).max, uint256(type(uint16).max) + 1
            )
        );
        new ERC1967Proxy(impl, data);
    }

    function test_WhenMembersContainTheZeroAddress() external {
        // it should accept it (no member validation, finding F8).
        Multisig plugin =
            _deployMultisig(dao, _members(alice, address(0)), _settings(false, 2), _daoTarget(), PLUGIN_METADATA);
        assertTrue(plugin.isListed(address(0)));
        assertEq(plugin.addresslistLength(), 2);
    }

    function test_RevertWhen_TargetIsTheDaoWithDelegateCall() external {
        // it should revert, the plugin would be bricked.
        address impl = address(implementation);
        IPlugin.TargetConfig memory target =
            IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.DelegateCall});
        bytes memory data = abi.encodeCall(
            Multisig.initialize, (IDAO(address(dao)), _members(alice), _settings(false, 1), target, PLUGIN_METADATA)
        );
        vm.expectRevert(abi.encodeWithSelector(PluginUUPSUpgradeable.InvalidTargetConfig.selector, target));
        new ERC1967Proxy(impl, data);
    }

    function test_WhenTargetIsTheZeroAddress() external {
        // it should store it and resolve the effective target to the DAO with a call.
        IPlugin.TargetConfig memory target =
            IPlugin.TargetConfig({target: address(0), operation: IPlugin.Operation.DelegateCall});
        Multisig plugin = _deployMultisig(dao, _members(alice), _settings(false, 1), target, PLUGIN_METADATA);

        assertEq(plugin.getCurrentTargetConfig().target, address(0), "current");
        assertEq(uint8(plugin.getCurrentTargetConfig().operation), uint8(IPlugin.Operation.DelegateCall), "currentOp");
        assertEq(plugin.getTargetConfig().target, address(dao), "effective");
        assertEq(uint8(plugin.getTargetConfig().operation), uint8(IPlugin.Operation.Call), "effectiveOp");
    }
}
