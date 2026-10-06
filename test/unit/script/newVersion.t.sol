// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PlaceholderSetup} from "@aragon/osx/framework/plugin/repo/placeholder/PlaceholderSetup.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import {Multisig} from "../../../src/Multisig.sol";
import {MultisigSetup} from "../../../src/MultisigSetup.sol";
import {BaseScript} from "../../../script/Base.sol";
import {PluginSettings} from "../../../script/PluginSettings.sol";
import {NewVersionHarness} from "../../utils/harness/NewVersionHarness.sol";
import {BaseTest} from "../../BaseTest.t.sol";

/// @dev `createVersion` assigns the build number on-chain: `NewVersion.s.sol` must publish exactly as many
///      builds as needed for the setup to land on `VERSION_BUILD`, and refuse to run once it exists.
///      The BaseTest DAO and its Multisig play the management DAO, which maintains the repo.
contract NewVersion_Script_UnitTest is BaseTest {
    bytes internal constant BUILD_METADATA = "ipfs://build";
    bytes internal constant RELEASE_METADATA = "ipfs://release";

    NewVersionHarness internal newVersion;
    PluginRepo internal repo;
    PlaceholderSetup internal previousSetup;
    MultisigSetup internal newSetup;

    function setUp() public override {
        super.setUp();
        if (vm.envOr("DEPLOYER_KEY", uint256(0)) == 0) vm.setEnv("DEPLOYER_KEY", vm.toString(uint256(1)));
        newVersion = new NewVersionHarness();

        repo = PluginRepo(
            address(new ERC1967Proxy(address(new PluginRepo()), abi.encodeCall(PluginRepo.initialize, (address(dao)))))
        );
        previousSetup = new PlaceholderSetup();
        newSetup = new MultisigSetup();
    }

    function _publishPreviousBuilds(uint256 _count) internal {
        for (uint256 i; i < _count; ++i) {
            vm.prank(address(dao));
            repo.createVersion(PluginSettings.VERSION_RELEASE, address(previousSetup), "b", RELEASE_METADATA);
        }
    }

    function _actionsFor(uint256 _count) internal view returns (Action[] memory) {
        return
            newVersion.exposed_createVersionActions(repo, address(newSetup), _count, BUILD_METADATA, RELEASE_METADATA);
    }

    /// @dev Submits the printed calldata as alice (a member), approves as bob, executes.
    function _runProposal(uint256 _count) internal {
        bytes memory data = newVersion.exposed_proposalCalldata(
            _actionsFor(_count), PROPOSAL_METADATA, uint64(block.timestamp + 30 days)
        );

        vm.prank(alice);
        (bool ok, bytes memory ret) = address(multisig).call(data);
        assertTrue(ok, "proposal creation");
        uint256 proposalId = abi.decode(ret, (uint256));

        assertTrue(multisig.hasApproved(proposalId, alice), "submitter approved");
        _approve(proposalId, bob);
        vm.prank(carol);
        multisig.execute(proposalId);
    }

    function _setupOf(uint16 _build) internal view returns (address) {
        return repo.getVersion(PluginRepo.Tag(PluginSettings.VERSION_RELEASE, _build)).pluginSetup;
    }

    function _expectInvalidBuild(uint256 _latestBuild) internal {
        vm.expectRevert(
            abi.encodeWithSelector(BaseScript.InvalidVersionBuild.selector, PluginSettings.VERSION_BUILD, _latestBuild)
        );
    }

    function test_WhenTheRepoIsOneBuildBehind() external {
        // it should publish a single build, landing on VERSION_BUILD.
        _publishPreviousBuilds(PluginSettings.VERSION_BUILD - 1);
        assertEq(newVersion.exposed_buildsToPublish(repo), 1, "builds to publish");

        _runProposal(1);

        assertEq(repo.buildCount(PluginSettings.VERSION_RELEASE), PluginSettings.VERSION_BUILD, "build count");
        assertEq(_setupOf(PluginSettings.VERSION_BUILD), address(newSetup), "new build");
        assertEq(_setupOf(PluginSettings.VERSION_BUILD - 1), address(previousSetup), "previous untouched");
    }

    function test_WhenTheRepoIsMoreThanOneBuildBehind() external {
        // it should fill the gap with the same setup and land on VERSION_BUILD.
        _publishPreviousBuilds(PluginSettings.VERSION_BUILD - 2);
        assertEq(newVersion.exposed_buildsToPublish(repo), 2, "builds to publish");

        _runProposal(2);

        assertEq(repo.buildCount(PluginSettings.VERSION_RELEASE), PluginSettings.VERSION_BUILD, "build count");
        assertEq(_setupOf(PluginSettings.VERSION_BUILD), address(newSetup), "new build");
        assertEq(_setupOf(PluginSettings.VERSION_BUILD - 1), address(newSetup), "gap build");

        // and it refuses to run again.
        _expectInvalidBuild(PluginSettings.VERSION_BUILD);
        newVersion.exposed_buildsToPublish(repo);
    }

    function test_RevertWhen_TheVersionIsAlreadyPublished() external {
        // it should revert, publishing again would create VERSION_BUILD + 1.
        _publishPreviousBuilds(PluginSettings.VERSION_BUILD);
        _expectInvalidBuild(PluginSettings.VERSION_BUILD);
        newVersion.exposed_buildsToPublish(repo);
    }

    function test_RevertWhen_TheRepoIsAheadOfTheVersion() external {
        // it should revert.
        _publishPreviousBuilds(PluginSettings.VERSION_BUILD + 1);
        _expectInvalidBuild(PluginSettings.VERSION_BUILD + 1);
        newVersion.exposed_buildsToPublish(repo);
    }

    function test_WhenBuildingTheActions() external view {
        // it should target the repo with createVersion and no value, once per build.
        Action[] memory actions = _actionsFor(3);
        assertEq(actions.length, 3, "count");
        bytes memory expected = abi.encodeCall(
            PluginRepo.createVersion,
            (PluginSettings.VERSION_RELEASE, address(newSetup), BUILD_METADATA, RELEASE_METADATA)
        );
        for (uint256 i; i < actions.length; ++i) {
            assertEq(actions[i].to, address(repo), "to");
            assertEq(actions[i].value, 0, "value");
            assertEq(actions[i].data, expected, "data");
        }
    }

    function test_WhenBuildingTheProposalCalldata() external {
        // it should create a proposal with the metadata, the actions and the submitter's approval, not executed.
        _publishPreviousBuilds(PluginSettings.VERSION_BUILD - 1);
        Action[] memory actions = _actionsFor(1);
        uint64 endDate = uint64(block.timestamp + 30 days);
        bytes memory data = newVersion.exposed_proposalCalldata(actions, PROPOSAL_METADATA, endDate);

        uint256 expectedId = _expectedProposalId(actions, PROPOSAL_METADATA);
        vm.prank(alice);
        (bool ok, bytes memory ret) = address(multisig).call(data);
        assertTrue(ok, "submission");
        assertEq(abi.decode(ret, (uint256)), expectedId, "id");

        (
            bool executed,
            uint16 approvals,
            Multisig.ProposalParameters memory parameters,
            Action[] memory stored,
            uint256 allowFailureMap,
        ) = multisig.getProposal(expectedId);
        assertFalse(executed, "not executed");
        assertEq(approvals, 1, "submitter approval");
        assertEq(allowFailureMap, 0, "no failure allowed");
        assertEq(parameters.startDate, block.timestamp, "starts now");
        assertEq(parameters.endDate, endDate, "end date");
        assertEq(stored.length, 1, "actions");
        assertEq(stored[0].data, actions[0].data, "action data");
    }
}
