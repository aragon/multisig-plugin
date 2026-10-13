// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {IERC1967Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC1967Upgradeable.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";

import {Multisig} from "../../../../../src/Multisig.sol";

contract Upgradeability_Multisig_UnitTest is BaseTest {
    /// @dev Expected slots of the audited build 3 (`fffc680`). Obtained by compiling `Multisig.sol` and
    ///      `IMultisig.sol` from commit fffc680 in a scratch Foundry project with this repo's `lib/` and running
    ///      `forge inspect src/Multisig.sol:Multisig storageLayout`. The current `src/` produces the same layout.
    uint256 internal constant DAO_SLOT = 201;
    uint256 internal constant CURRENT_TARGET_CONFIG_SLOT = 251;
    uint256 internal constant PROPOSALS_SLOT = 401;
    uint256 internal constant MULTISIG_SETTINGS_SLOT = 402;
    uint256 internal constant LAST_MULTISIG_SETTINGS_CHANGE_SLOT = 403;

    Multisig internal newImplementation;

    function setUp() public override {
        super.setUp();
        newImplementation = new Multisig();
    }

    function _currentImplementation() internal view returns (address) {
        return address(uint160(uint256(vm.load(address(multisig), IMPLEMENTATION_SLOT))));
    }

    function test_RevertWhen_UpgradingWithoutPermission() external {
        // it should revert with DaoUnauthorized.
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(multisig), unauthorized, UPGRADE_PLUGIN_PERMISSION_ID
            )
        );
        vm.prank(unauthorized);
        multisig.upgradeTo(address(newImplementation));
    }

    function test_RevertWhen_TheDaoUpgradesWithoutPermission() external {
        // it should revert, the installation does not grant UPGRADE_PLUGIN_PERMISSION to the DAO.
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(multisig), address(dao), UPGRADE_PLUGIN_PERMISSION_ID
            )
        );
        vm.prank(address(dao));
        multisig.upgradeTo(address(newImplementation));
    }

    function test_RevertWhen_UpgradingAndCallingWithoutPermission() external {
        // it should revert with DaoUnauthorized.
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(multisig), unauthorized, UPGRADE_PLUGIN_PERMISSION_ID
            )
        );
        vm.prank(unauthorized);
        multisig.upgradeToAndCall(address(newImplementation), abi.encodeWithSignature("addresslistLength()"));
    }

    modifier givenTheCallerHasUpgradePermission() {
        _grant(address(multisig), manager, UPGRADE_PLUGIN_PERMISSION_ID);
        _;
    }

    function test_WhenUpgrading() external givenTheCallerHasUpgradePermission {
        // it should change the implementation slot and emit Upgraded.
        // it should preserve members, settings, metadata and target config.
        address oldImplementation = _currentImplementation();

        vm.expectEmit(address(multisig));
        emit IERC1967Upgradeable.Upgraded(address(newImplementation));
        vm.prank(manager);
        multisig.upgradeTo(address(newImplementation));

        assertNotEq(oldImplementation, address(newImplementation), "different");
        assertEq(_currentImplementation(), address(newImplementation), "slot");
        assertEq(multisig.implementation(), address(newImplementation), "getter");

        assertEq(multisig.addresslistLength(), 3, "length");
        assertTrue(multisig.isListed(alice), "alice");
        (bool onlyListed, uint16 minApprovals) = multisig.multisigSettings();
        assertTrue(onlyListed, "onlyListed");
        assertEq(minApprovals, 2, "minApprovals");
        assertEq(multisig.getMetadata(), PLUGIN_METADATA, "metadata");
        assertEq(multisig.getCurrentTargetConfig().target, address(dao), "target");
    }

    function test_WhenUpgradingAndCalling() external givenTheCallerHasUpgradePermission {
        // it should change the implementation and run the call.
        vm.prank(manager);
        multisig.upgradeToAndCall(address(newImplementation), abi.encodeWithSignature("addresslistLength()"));
        assertEq(_currentImplementation(), address(newImplementation));
    }

    function test_RevertWhen_ReinitializingThroughUpgradeToAndCall() external givenTheCallerHasUpgradePermission {
        // it should revert, a build 3 proxy has already consumed reinitializer(2).
        bytes memory data = abi.encodeCall(Multisig.initializeFrom, (2, abi.encode(_daoTarget(), bytes(""))));
        vm.expectRevert("Initializable: contract is already initialized");
        vm.prank(manager);
        multisig.upgradeToAndCall(address(newImplementation), data);
    }

    function test_RevertWhen_TheNewImplementationIsNotUups() external givenTheCallerHasUpgradePermission {
        // it should revert.
        vm.expectRevert("ERC1967Upgrade: new implementation is not UUPS");
        vm.prank(manager);
        multisig.upgradeTo(address(actionTarget));
    }

    function test_RevertWhen_CallingUpgradeOnTheImplementation() external {
        // it should revert, upgrades must go through the proxy.
        Multisig implementation = Multisig(_currentImplementation());
        vm.expectRevert("Function must be called through delegatecall");
        implementation.upgradeTo(address(newImplementation));
    }

    function test_WhenReadingTheStorageLayout() external {
        // it should keep the audited build 3 slots for the DAO, target config, settings and proposals.
        IPlugin.TargetConfig memory target =
            IPlugin.TargetConfig({target: address(actionTarget), operation: IPlugin.Operation.DelegateCall});
        vm.prank(address(dao));
        multisig.setTargetConfig(target);
        vm.roll(block.number + 5);
        _updateSettings(false, 3);
        vm.roll(block.number + 1);

        // dao_
        assertEq(address(uint160(uint256(vm.load(address(multisig), bytes32(DAO_SLOT))))), address(dao), "dao");

        // Truncating casts below are intended: they extract packed fields from raw storage words.
        // forge-lint: disable-start(unsafe-typecast)
        // currentTargetConfig: address (20 bytes) + operation (uint8) packed
        uint256 targetWord = uint256(vm.load(address(multisig), bytes32(CURRENT_TARGET_CONFIG_SLOT)));
        assertEq(address(uint160(targetWord)), address(actionTarget), "target");
        assertEq(uint8(targetWord >> 160), uint8(IPlugin.Operation.DelegateCall), "operation");

        // multisigSettings: onlyListed (bool) + minApprovals (uint16) packed
        uint256 settingsWord = uint256(vm.load(address(multisig), bytes32(MULTISIG_SETTINGS_SLOT)));
        assertEq(uint8(settingsWord), 0, "onlyListed");
        assertEq(uint16(settingsWord >> 8), 3, "minApprovals");

        // lastMultisigSettingsChange (uint64)
        assertEq(
            uint64(uint256(vm.load(address(multisig), bytes32(LAST_MULTISIG_SETTINGS_CHANGE_SLOT)))),
            multisig.lastMultisigSettingsChange(),
            "lastMultisigSettingsChange"
        );
        assertEq(multisig.lastMultisigSettingsChange(), block.number - 1, "lastMultisigSettingsChange value");

        // proposals[id]: executed + approvals | parameters | approvers | actions | allowFailureMap | targetConfig
        uint256 proposalId = _createProposal(alice, _actions(2), 5, true, false);
        uint256 base = uint256(keccak256(abi.encode(proposalId, PROPOSALS_SLOT)));

        uint256 word0 = uint256(vm.load(address(multisig), bytes32(base)));
        assertEq(uint8(word0), 0, "executed");
        assertEq(uint16(word0 >> 8), 1, "approvals");

        uint256 word1 = uint256(vm.load(address(multisig), bytes32(base + 1)));
        assertEq(uint16(word1), 3, "minApprovals");
        assertEq(uint64(word1 >> 16), block.number - 1, "snapshotBlock");
        assertEq(uint64(word1 >> 80), block.timestamp, "startDate");
        assertEq(uint64(word1 >> 144), block.timestamp + PROPOSAL_DURATION, "endDate");

        uint256 approverSlot = uint256(keccak256(abi.encode(alice, base + 2)));
        assertEq(uint256(vm.load(address(multisig), bytes32(approverSlot))), 1, "approvers[alice]");
        assertEq(uint256(vm.load(address(multisig), bytes32(base + 3))), 2, "actions.length");
        assertEq(uint256(vm.load(address(multisig), bytes32(base + 4))), 5, "allowFailureMap");

        uint256 proposalTargetWord = uint256(vm.load(address(multisig), bytes32(base + 5)));
        assertEq(address(uint160(proposalTargetWord)), address(actionTarget), "proposal target");
        assertEq(uint8(proposalTargetWord >> 160), uint8(IPlugin.Operation.DelegateCall), "proposal operation");
        // forge-lint: disable-end(unsafe-typecast)
    }
}
