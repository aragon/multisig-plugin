// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../BaseTest.t.sol";

import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";

import {Multisig} from "../../../src/Multisig.sol";
import {MultisigSetup} from "../../../src/MultisigSetup.sol";

/// @notice Shared helpers for the `MultisigSetup` unit tests.
abstract contract MultisigSetupBaseTest is BaseTest {
    MultisigSetup internal setup;

    function setUp() public virtual override {
        super.setUp();
        setup = new MultisigSetup();
        vm.label(address(setup), "MultisigSetup");
    }

    function _installData(
        address[] memory _memberList,
        bool _onlyListed,
        uint16 _minApprovals,
        IPlugin.TargetConfig memory _targetConfig,
        bytes memory _metadata
    ) internal pure returns (bytes memory) {
        return abi.encode(_memberList, _settings(_onlyListed, _minApprovals), _targetConfig, _metadata);
    }

    function _defaultInstallData() internal view returns (bytes memory) {
        return _installData(_members(alice, bob, carol), true, 2, _daoTarget(), PLUGIN_METADATA);
    }

    function _assertPermission(
        PermissionLib.MultiTargetPermission memory _actual,
        PermissionLib.Operation _operation,
        address _where,
        address _who,
        address _condition,
        bytes32 _permissionId,
        string memory _label
    ) internal pure {
        assertEq(uint8(_actual.operation), uint8(_operation), string.concat(_label, ": operation"));
        assertEq(_actual.where, _where, string.concat(_label, ": where"));
        assertEq(_actual.who, _who, string.concat(_label, ": who"));
        assertEq(_actual.condition, _condition, string.concat(_label, ": condition"));
        assertEq(_actual.permissionId, _permissionId, string.concat(_label, ": permissionId"));
    }
}
