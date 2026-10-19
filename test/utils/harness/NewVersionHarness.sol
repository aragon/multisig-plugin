// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import {NewVersion} from "../../../script/NewVersion.s.sol";

/// @notice Exposes the internal steps of `NewVersion.s.sol` to the tests.
contract NewVersionHarness is NewVersion {
    function exposed_buildsToPublish(PluginRepo _repo) external view returns (uint256) {
        return _buildsToPublish(_repo);
    }

    function exposed_createVersionActions(
        PluginRepo _repo,
        address _setup,
        uint256 _count,
        bytes memory _buildMetadata,
        bytes memory _releaseMetadata
    ) external pure returns (Action[] memory) {
        return _createVersionActions(_repo, _setup, _count, _buildMetadata, _releaseMetadata);
    }

    function exposed_publishedVersions(address _setup, uint256 _count)
        external
        view
        returns (ArtifactVersion[] memory)
    {
        return _publishedVersions(_setup, _count);
    }

    function exposed_proposalCalldata(Action[] memory _actions, bytes memory _metadata, uint64 _endDate)
        external
        pure
        returns (bytes memory)
    {
        return _proposalCalldata(_actions, _metadata, _endDate);
    }
}
