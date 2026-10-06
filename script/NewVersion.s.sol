// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import {MultisigSetup} from "../src/MultisigSetup.sol";
import {BaseScript} from "./Base.sol";
import {PluginSettings} from "./PluginSettings.sol";

/// @notice Deploys a new `MultisigSetup` (and implementation) on a network where the repo already
///         exists, and prints the management DAO proposal that publishes it as `VERSION_BUILD`.
///         Any member of the management DAO multisig can submit the printed calldata.
contract NewVersion is BaseScript {
    /// @dev Voting window of the management DAO proposal. The Multisig takes an absolute end date, so the window
    ///      counts from when the script runs, not from when the printed calldata is submitted.
    uint64 internal constant PROPOSAL_DURATION = 30 days;

    function run() external {
        _requireMetadata();
        multisigRepo = PluginRepo(vm.envAddress("MULTISIG_PLUGIN_REPO_ADDRESS"));
        address managementDao = vm.envAddress("MANAGEMENT_DAO_ADDRESS");
        address managementDaoMultisig = vm.envAddress("MANAGEMENT_DAO_MULTISIG_ADDRESS");

        uint256 buildCount = _buildsToPublish(multisigRepo);

        vm.startBroadcast(deployerPrivateKey);
        multisigSetup = new MultisigSetup();
        vm.stopBroadcast();

        console.log("- MultisigSetup:  ", address(multisigSetup));
        console.log("- Implementation: ", multisigSetup.implementation());
        console.log("- Version:        ", _versionString(PluginSettings.VERSION_RELEASE, PluginSettings.VERSION_BUILD));

        // The version only exists on-chain once the proposal below is executed.
        // Import this artifact into artifacts-hub (`just import-plugin`) only after that.
        _writeArtifact(managementDao, address(multisigSetup), multisigSetup.implementation());

        Action[] memory actions = _createVersionActions(
            multisigRepo,
            address(multisigSetup),
            buildCount,
            bytes(PluginSettings.BUILD_METADATA),
            bytes(PluginSettings.RELEASE_METADATA)
        );
        uint64 endDate = uint64(block.timestamp) + PROPOSAL_DURATION;
        bytes memory proposalCalldata = _proposalCalldata(actions, bytes(PluginSettings.PROPOSAL_METADATA), endDate);

        console.log("\nDAO action publishing this version (x", buildCount, "):");
        console.log("  to:   ", address(multisigRepo));
        console.logBytes(actions[0].data);
        if (buildCount > 1) {
            console.log("  The repo is behind: the same setup fills every missing build.");
        }

        console.log("\nManagement DAO multisig proposal:");
        console.log("  to:   ", managementDaoMultisig);
        console.log("  data:");
        console.logBytes(proposalCalldata);
        console.log("  metadata:", PluginSettings.PROPOSAL_METADATA);
        console.log("  allowFailureMap=0, approveProposal=true, tryExecution=false, startDate=now");
        console.log("  endDate (unix, now + 30 days):", uint256(endDate));
        console.log("\n  Proposal id salt (the id also depends on the submission block):");
        console.logBytes32(keccak256(abi.encode(actions, bytes(PluginSettings.PROPOSAL_METADATA))));

        console.log("\nSubmit it from a management DAO multisig member, e.g.:");
        console.log(
            string.concat("  cast send ", vm.toString(managementDaoMultisig), " <data> --rpc-url <RPC_URL> --ledger")
        );
    }

    /// @dev `createVersion` assigns the next build number itself. Returns how many builds must be
    ///      published for this setup to land on `VERSION_BUILD`; more than one when the repo is behind,
    ///      in which case the gap is filled with this same setup (the PSP treats updates between builds
    ///      of the same setup as UI-only). Reverts if `VERSION_BUILD` is already published.
    function _buildsToPublish(PluginRepo _repo) internal view returns (uint256) {
        uint256 latestBuild = _repo.buildCount(PluginSettings.VERSION_RELEASE);
        if (latestBuild >= PluginSettings.VERSION_BUILD) {
            revert InvalidVersionBuild(PluginSettings.VERSION_BUILD, latestBuild);
        }
        return PluginSettings.VERSION_BUILD - latestBuild;
    }

    function _createVersionActions(
        PluginRepo _repo,
        address _setup,
        uint256 _count,
        bytes memory _buildMetadata,
        bytes memory _releaseMetadata
    ) internal pure returns (Action[] memory actions) {
        bytes memory data = abi.encodeCall(
            PluginRepo.createVersion, (PluginSettings.VERSION_RELEASE, _setup, _buildMetadata, _releaseMetadata)
        );
        actions = new Action[](_count);
        for (uint256 i; i < _count; ++i) {
            actions[i] = Action({to: address(_repo), value: 0, data: data});
        }
    }

    /// @dev The 7-argument `createProposal` of the management DAO multisig. `abi.encodeCall` cannot pick
    ///      an overload, so the signature is spelled out; `test/unit/script` submits this exact calldata
    ///      to a real `Multisig` to prove it matches.
    function _proposalCalldata(Action[] memory _actions, bytes memory _metadata, uint64 _endDate)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature(
            "createProposal(bytes,(address,uint256,bytes)[],uint256,bool,bool,uint64,uint64)",
            _metadata,
            _actions,
            uint256(0),
            true,
            false,
            uint64(0),
            _endDate
        );
    }
}
