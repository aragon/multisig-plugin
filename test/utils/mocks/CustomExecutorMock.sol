// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

/// @notice Stand-in for a custom execution target (`IPlugin.TargetConfig.target`).
/// @dev Stateless on purpose: under `DelegateCall` it runs in the plugin's storage context.
///      `self` in the event tells whether it ran as a call (mock address) or a delegatecall (plugin address).
contract CustomExecutorMock {
    /// @notice A failure map value that makes the mock revert, to test failing executions.
    uint256 public constant REVERT_FAILURE_MAP = type(uint256).max;

    error FailedCustom();

    event ExecutedCustom(address self, address sender, bytes32 callId, uint256 actionCount, uint256 allowFailureMap);

    function execute(bytes32 _callId, Action[] memory _actions, uint256 _allowFailureMap)
        external
        returns (bytes[] memory execResults, uint256 failureMap)
    {
        if (_allowFailureMap == REVERT_FAILURE_MAP) revert FailedCustom();

        emit ExecutedCustom(address(this), msg.sender, _callId, _actions.length, _allowFailureMap);
        execResults = new bytes[](_actions.length);
        failureMap = 0;
    }
}
