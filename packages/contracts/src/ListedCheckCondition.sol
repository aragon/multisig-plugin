// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {Multisig} from "./Multisig.sol";

import {PermissionCondition} from "@aragon/osx-commons-contracts/src/permission/condition/PermissionCondition.sol";

contract ListedCheckCondition is PermissionCondition {
    Multisig private immutable multisig;

    constructor(address _multisig) {
        multisig = Multisig(_multisig);
    }

    function isGranted(
        address _where,
        address _who,
        bytes32 _permissionId,
        bytes calldata _data
    ) public view override returns (bool) {
        (_where, _data, _permissionId);

        (bool onlyListed, ) = multisig.multisigSettings();

        if (onlyListed && !multisig.isListed(_who)) {
            return false;
        }

        return true;
    }
}
