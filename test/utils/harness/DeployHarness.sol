// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

import {Deploy} from "../../../script/Deploy.s.sol";

/// @notice Exposes the internal steps of `Deploy.s.sol` to the tests.
contract DeployHarness is Deploy {
    function exposed_requireMetadata() external pure {
        _requireMetadata();
    }

    function exposed_ensName(string memory _subdomain) external pure returns (string memory) {
        return _ensName(_subdomain);
    }

    function exposed_ensSubdomain() external view returns (string memory) {
        return _ensSubdomain();
    }

    function exposed_publish(
        PluginRepo _repo,
        address _setup,
        bytes memory _buildMetadata,
        bytes memory _releaseMetadata
    ) external {
        _publish(_repo, _setup, _buildMetadata, _releaseMetadata);
    }

    function exposed_transferOwnership(PluginRepo _repo, address _managementDao, address _deployer) external {
        _transferOwnership(_repo, _managementDao, _deployer);
    }

    function exposed_publishedVersions(address _setup) external view returns (ArtifactVersion[] memory) {
        return _publishedVersions(_setup);
    }

    function exposed_writeArtifact(
        PluginRepo _repo,
        address _maintainer,
        string memory _ens,
        ArtifactVersion[] memory _versions
    ) external {
        multisigRepo = _repo;
        repoEnsName = _ens;
        _writeArtifact(_maintainer, _versions);
    }
}
