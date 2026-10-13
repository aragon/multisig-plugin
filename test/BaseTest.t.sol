// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";

import {Multisig} from "../src/Multisig.sol";
import {ListedCheckCondition} from "../src/ListedCheckCondition.sol";

import {Constants} from "./utils/Constants.sol";
import {ActionTarget} from "./utils/mocks/ActionTarget.sol";

/// @notice Shared fixture: a real DAO with a Multisig plugin wired exactly like `MultisigSetup` does.
/// @dev Members: alice, bob, carol. Settings: onlyListed = true, minApprovals = 2. Target: the DAO (call).
///      The chain starts at `START_BLOCK + 1`, so proposals can be created right away
///      (creation is forbidden in the block where the settings changed).
contract BaseTest is Constants, Test {
    address internal manager; // DAO root
    address internal alice;
    address internal bob;
    address internal carol;
    address internal dave; // never a member by default
    address internal unauthorized;

    DAO internal dao;
    Multisig internal multisig;
    ListedCheckCondition internal listedCheckCondition;
    ActionTarget internal actionTarget;

    function setUp() public virtual {
        vm.roll(START_BLOCK);
        vm.warp(START_TIMESTAMP);

        manager = makeAddr("manager");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        dave = makeAddr("dave");
        unauthorized = makeAddr("unauthorized");

        dao = _deployDao(manager);
        actionTarget = new ActionTarget();

        multisig = _deployMultisig(dao, _members(alice, bob, carol), _settings(true, 2), _daoTarget(), PLUGIN_METADATA);
        listedCheckCondition = new ListedCheckCondition(address(multisig));
        _grantSetupPermissions(multisig, address(listedCheckCondition));

        vm.label(address(dao), "DAO");
        vm.label(address(multisig), "Multisig");
        vm.label(address(listedCheckCondition), "ListedCheckCondition");
        vm.label(address(actionTarget), "ActionTarget");

        vm.roll(START_BLOCK + 1);
    }

    // ==== Deployment helpers ====

    function _deployDao(address _root) internal returns (DAO) {
        return
            DAO(
                payable(new ERC1967Proxy(
                        address(new DAO()), abi.encodeCall(DAO.initialize, ("", _root, address(0), ""))
                    ))
            );
    }

    function _deployMultisig(
        DAO _dao,
        address[] memory _memberList,
        Multisig.MultisigSettings memory _multisigSettings,
        IPlugin.TargetConfig memory _targetConfig,
        bytes memory _metadata
    ) internal returns (Multisig) {
        return Multisig(
            address(
                new ERC1967Proxy(
                    address(new Multisig()),
                    abi.encodeCall(
                        Multisig.initialize,
                        (IDAO(address(_dao)), _memberList, _multisigSettings, _targetConfig, _metadata)
                    )
                )
            )
        );
    }

    /// @dev Mirrors the permissions granted by `MultisigSetup.prepareInstallation`.
    function _grantSetupPermissions(Multisig _multisig, address _condition) internal {
        PermissionLib.MultiTargetPermission[] memory permissions = new PermissionLib.MultiTargetPermission[](6);
        permissions[0] = _permission(
            PermissionLib.Operation.Grant, address(_multisig), address(dao), UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
        );
        permissions[1] =
            _permission(PermissionLib.Operation.Grant, address(dao), address(_multisig), EXECUTE_PERMISSION_ID);
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.GrantWithCondition,
            where: address(_multisig),
            who: ANY_ADDR,
            condition: _condition,
            permissionId: CREATE_PROPOSAL_PERMISSION_ID
        });
        permissions[3] = _permission(
            PermissionLib.Operation.Grant, address(_multisig), address(dao), SET_TARGET_CONFIG_PERMISSION_ID
        );
        permissions[4] =
            _permission(PermissionLib.Operation.Grant, address(_multisig), address(dao), SET_METADATA_PERMISSION_ID);
        permissions[5] =
            _permission(PermissionLib.Operation.Grant, address(_multisig), ANY_ADDR, EXECUTE_PROPOSAL_PERMISSION_ID);

        vm.prank(manager);
        dao.applyMultiTargetPermissions(permissions);
    }

    // ==== Permission helpers ====

    function _permission(PermissionLib.Operation _operation, address _where, address _who, bytes32 _permissionId)
        internal
        pure
        returns (PermissionLib.MultiTargetPermission memory)
    {
        return PermissionLib.MultiTargetPermission({
            operation: _operation, where: _where, who: _who, condition: NO_CONDITION, permissionId: _permissionId
        });
    }

    function _grant(address _where, address _who, bytes32 _permissionId) internal {
        vm.prank(manager);
        dao.grant(_where, _who, _permissionId);
    }

    function _revoke(address _where, address _who, bytes32 _permissionId) internal {
        vm.prank(manager);
        dao.revoke(_where, _who, _permissionId);
    }

    // ==== Settings helpers (called as the DAO, which holds UPDATE_MULTISIG_SETTINGS_PERMISSION) ====

    function _updateSettings(bool _onlyListed, uint16 _minApprovals) internal {
        vm.prank(address(dao));
        multisig.updateMultisigSettings(_settings(_onlyListed, _minApprovals));
    }

    function _addMembers(address[] memory _memberList) internal {
        vm.prank(address(dao));
        multisig.addAddresses(_memberList);
    }

    function _removeMembers(address[] memory _memberList) internal {
        vm.prank(address(dao));
        multisig.removeAddresses(_memberList);
    }

    // ==== Proposal helpers ====

    /// @dev Creates a proposal as `_creator` with the default actions and window, without approving.
    function _createProposal(address _creator) internal returns (uint256) {
        return _createProposal(_creator, _actions(1), 0, false, false);
    }

    function _createProposal(
        address _creator,
        Action[] memory _actionList,
        uint256 _allowFailureMap,
        bool _approveProposal,
        bool _tryExecution
    ) internal returns (uint256) {
        vm.prank(_creator);
        return multisig.createProposal(
            PROPOSAL_METADATA,
            _actionList,
            _allowFailureMap,
            _approveProposal,
            _tryExecution,
            0,
            uint64(block.timestamp) + PROPOSAL_DURATION
        );
    }

    function _approve(uint256 _proposalId, address _approver) internal {
        vm.prank(_approver);
        multisig.approve(_proposalId, false);
    }

    /// @dev Creates a proposal and gathers `minApprovals` (2) approvals from alice and bob.
    function _createPassedProposal() internal returns (uint256 proposalId) {
        proposalId = _createProposal(alice, _actions(1), 0, true, false);
        _approve(proposalId, bob);
    }

    /// @dev `_count` actions calling `actionTarget.setValue(i + 1)`.
    function _actions(uint256 _count) internal view returns (Action[] memory actionList) {
        actionList = new Action[](_count);
        for (uint256 i; i < _count; ++i) {
            actionList[i] =
                Action({to: address(actionTarget), value: 0, data: abi.encodeCall(ActionTarget.setValue, (i + 1))});
        }
    }

    function _failingAction() internal view returns (Action memory) {
        return Action({to: address(actionTarget), value: 0, data: abi.encodeCall(ActionTarget.fail, ())});
    }

    /// @dev The proposal ID formula, written independently from `ProposalUpgradeable._createProposalId`.
    function _expectedProposalId(Action[] memory _actionList, bytes memory _metadata) internal view returns (uint256) {
        bytes32 salt = keccak256(abi.encode(_actionList, _metadata));
        return uint256(keccak256(abi.encode(block.chainid, block.number, address(multisig), salt)));
    }

    // ==== Data helpers ====

    function _settings(bool _onlyListed, uint16 _minApprovals)
        internal
        pure
        returns (Multisig.MultisigSettings memory)
    {
        return Multisig.MultisigSettings({onlyListed: _onlyListed, minApprovals: _minApprovals});
    }

    function _daoTarget() internal view returns (IPlugin.TargetConfig memory) {
        return IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call});
    }

    function _members(address _a) internal pure returns (address[] memory list) {
        list = new address[](1);
        list[0] = _a;
    }

    function _members(address _a, address _b) internal pure returns (address[] memory list) {
        list = new address[](2);
        list[0] = _a;
        list[1] = _b;
    }

    function _members(address _a, address _b, address _c) internal pure returns (address[] memory list) {
        list = new address[](3);
        list[0] = _a;
        list[1] = _b;
        list[2] = _c;
    }

    /// @dev `_count` distinct addresses starting at `_offset` (deterministic, never a labelled user).
    function _generatedMembers(uint256 _count, uint256 _offset) internal pure returns (address[] memory list) {
        list = new address[](_count);
        for (uint256 i; i < _count; ++i) {
            // Small values (< 2^160): the cast cannot truncate.
            // forge-lint: disable-next-line(unsafe-typecast)
            list[i] = address(uint160(0x10000 + _offset + i));
        }
    }
}
