// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {IPermissionCondition} from "@aragon/osx-commons-contracts/src/permission/condition/IPermissionCondition.sol";
import {IProtocolVersion} from "@aragon/osx-commons-contracts/src/utils/versioning/IProtocolVersion.sol";

import {Multisig} from "../../../../../src/Multisig.sol";
import {ListedCheckCondition} from "../../../../../src/ListedCheckCondition.sol";

contract IsGranted_ListedCheckCondition_UnitTest is BaseTest {
    bytes32 internal constant RANDOM_PERMISSION_ID = keccak256("RANDOM_PERMISSION");

    function _isGranted(address _who) internal view returns (bool) {
        return listedCheckCondition.isGranted(address(multisig), _who, CREATE_PROPOSAL_PERMISSION_ID, "");
    }

    function test_WhenDeployed() external view {
        // it should advertise IPermissionCondition and IProtocolVersion.
        assertTrue(
            listedCheckCondition.supportsInterface(bytes4(keccak256("isGranted(address,address,bytes32,bytes)"))),
            "IPermissionCondition"
        );
        assertTrue(listedCheckCondition.supportsInterface(type(IPermissionCondition).interfaceId), "type()");
        assertTrue(listedCheckCondition.supportsInterface(IPROTOCOL_VERSION_ID), "IProtocolVersion");
        assertTrue(
            listedCheckCondition.supportsInterface(type(IProtocolVersion).interfaceId), "IProtocolVersion type()"
        );
        assertTrue(listedCheckCondition.supportsInterface(IERC165_ID), "IERC165");
        assertFalse(listedCheckCondition.supportsInterface(0xffffffff), "0xffffffff");
    }

    modifier givenOnlyListedIsTrue() {
        _;
    }

    function test_WhenTheCallerIsListed() external view givenOnlyListedIsTrue {
        // it should grant.
        assertTrue(_isGranted(alice));
        assertTrue(_isGranted(bob));
        assertTrue(_isGranted(carol));
    }

    function test_WhenTheCallerIsNotListed() external view givenOnlyListedIsTrue {
        // it should not grant.
        assertFalse(_isGranted(dave));
        assertFalse(_isGranted(address(0)));
        assertFalse(_isGranted(address(dao)));
    }

    function test_WhenTheCallerWasRemoved() external givenOnlyListedIsTrue {
        // it should not grant from the block of the removal on (uses the live list, not a snapshot).
        _removeMembers(_members(carol));
        assertFalse(_isGranted(carol), "removed");
        assertTrue(multisig.isListedAtBlock(carol, block.number - 1), "still listed at the previous block");
    }

    function test_WhenTheCallerIsAddedInTheSameBlock() external givenOnlyListedIsTrue {
        // it should grant immediately.
        assertFalse(_isGranted(dave), "before");
        _addMembers(_members(dave));
        assertTrue(_isGranted(dave), "after");
    }

    modifier givenOnlyListedIsFalse() {
        _updateSettings(false, 2);
        _;
    }

    function test_WhenAnyCaller() external givenOnlyListedIsFalse {
        // it should grant listed and unlisted callers alike.
        assertTrue(_isGranted(alice), "listed");
        assertTrue(_isGranted(dave), "unlisted");
        assertTrue(_isGranted(address(0)), "zero address");
        assertTrue(_isGranted(ANY_ADDR), "any address");
    }

    function test_WhenSettingsToggleBackToOnlyListed() external givenOnlyListedIsFalse {
        // it should react live to the setting.
        assertTrue(_isGranted(dave), "open");
        _updateSettings(true, 2);
        assertFalse(_isGranted(dave), "closed");
        assertTrue(_isGranted(alice), "member");
    }

    function test_WhenWhereIdAndDataAreArbitrary() external view {
        // it should ignore `_where`, `_permissionId` and `_data`.
        bytes memory garbage = hex"deadbeef";
        assertTrue(listedCheckCondition.isGranted(address(0), alice, RANDOM_PERMISSION_ID, garbage), "member");
        assertTrue(listedCheckCondition.isGranted(address(dao), alice, bytes32(0), ""), "member, dao");
        assertFalse(listedCheckCondition.isGranted(address(0), dave, RANDOM_PERMISSION_ID, garbage), "non member");
        assertFalse(listedCheckCondition.isGranted(address(multisig), dave, CREATE_PROPOSAL_PERMISSION_ID, ""), "nm");
    }

    function test_WhenBoundToAnotherPlugin() external {
        // it should only read the plugin it was deployed for.
        Multisig other = _deployMultisig(dao, _members(dave), _settings(true, 1), _daoTarget(), PLUGIN_METADATA);
        ListedCheckCondition otherCondition = new ListedCheckCondition(address(other));

        assertTrue(otherCondition.isGranted(address(multisig), dave, CREATE_PROPOSAL_PERMISSION_ID, ""), "dave");
        assertFalse(otherCondition.isGranted(address(multisig), alice, CREATE_PROPOSAL_PERMISSION_ID, ""), "alice");
        // The original condition is unaffected.
        assertFalse(_isGranted(dave), "original dave");
    }

    function test_RevertWhen_BoundToAnAddressThatIsNotAMultisig() external {
        // it should deploy (no validation) but revert on use.
        // FINDING: the constructor accepts any address, including EOAs and address(0).
        ListedCheckCondition broken = new ListedCheckCondition(address(0));
        vm.expectRevert();
        broken.isGranted(address(multisig), alice, CREATE_PROPOSAL_PERMISSION_ID, "");
    }

    function test_WhenUsedThroughThePermissionManager() external {
        // it should gate createProposal: listed callers pass, others get DaoUnauthorized.
        assertTrue(dao.hasPermission(address(multisig), alice, CREATE_PROPOSAL_PERMISSION_ID, ""), "alice via DAO");
        assertFalse(dao.hasPermission(address(multisig), dave, CREATE_PROPOSAL_PERMISSION_ID, ""), "dave via DAO");

        _createProposal(alice);

        vm.expectRevert(
            abi.encodeWithSignature(
                "DaoUnauthorized(address,address,address,bytes32)",
                address(dao),
                address(multisig),
                dave,
                CREATE_PROPOSAL_PERMISSION_ID
            )
        );
        _createProposal(dave);
    }

    function test_WhenTheConditionCallReverts() external {
        // it should deny through the permission manager (try/catch), not bubble the revert.
        ListedCheckCondition broken = new ListedCheckCondition(address(0xdead));
        vm.startPrank(manager);
        dao.revoke(address(multisig), ANY_ADDR, CREATE_PROPOSAL_PERMISSION_ID);
        dao.grantWithCondition(address(multisig), ANY_ADDR, CREATE_PROPOSAL_PERMISSION_ID, broken);
        vm.stopPrank();

        assertFalse(dao.hasPermission(address(multisig), alice, CREATE_PROPOSAL_PERMISSION_ID, ""));
    }
}
