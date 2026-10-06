// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {PermissionCondition} from "@aragon/osx-commons-contracts/src/permission/condition/PermissionCondition.sol";

/// @notice Grants only when the checked calldata starts with a given selector.
/// @dev Used to observe which calldata the plugin forwards to `hasPermission`.
contract SelectorCondition is PermissionCondition {
    bytes4 public immutable SELECTOR;

    constructor(bytes4 _selector) {
        SELECTOR = _selector;
    }

    function isGranted(address, address, bytes32, bytes calldata _data) public view override returns (bool) {
        return _data.length >= 4 && bytes4(_data[:4]) == SELECTOR;
    }
}
