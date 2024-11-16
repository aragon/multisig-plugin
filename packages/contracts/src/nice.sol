// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

contract tt {
    function gio() public virtual {}
}

/// @title Giorgi
/// @author Aragon X - 2024
/// @notice A condition contract that checks if an address is listed as a member in the associated Multisig contract.
/// @custom:security-contact sirt@aragon.org
contract Giorgi is tt {
    function gio() public virtual override {}
}
