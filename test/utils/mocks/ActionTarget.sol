// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {IMultisig} from "../../../src/IMultisig.sol";

/// @notice Target of proposal actions: records calls, can fail, and can re-enter the multisig.
contract ActionTarget {
    uint256 public value;
    address public lastCaller;

    error ActionReverted();

    event ValueSet(uint256 value, address caller);

    function setValue(uint256 _value) external payable {
        value = _value;
        lastCaller = msg.sender;
        emit ValueSet(_value, msg.sender);
    }

    function fail() external pure {
        revert ActionReverted();
    }

    function reenterExecute(IMultisig _multisig, uint256 _proposalId) external {
        _multisig.execute(_proposalId);
    }

    function reenterApprove(IMultisig _multisig, uint256 _proposalId) external {
        _multisig.approve(_proposalId, true);
    }
}
