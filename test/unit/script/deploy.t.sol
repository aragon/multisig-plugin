// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PlaceholderSetup} from "@aragon/osx/framework/plugin/repo/placeholder/PlaceholderSetup.sol";

import {MultisigSetup} from "../../../src/MultisigSetup.sol";
import {BaseScript} from "../../../script/Base.sol";
import {PluginSettings} from "../../../script/PluginSettings.sol";
import {DeployHarness} from "../../utils/harness/DeployHarness.sol";

/// @dev The steps of `Deploy.s.sol`. The full `run()` (factory, ENS) is covered by the fork tests.
contract Deploy_Script_UnitTest is Test {
    bytes internal constant BUILD_METADATA = "ipfs://build";
    bytes internal constant RELEASE_METADATA = "ipfs://release";

    DeployHarness internal deploy;
    PluginRepo internal repo;
    MultisigSetup internal setup;
    address internal managementDao = makeAddr("managementDao");

    function setUp() public {
        // `BaseScript` reads the deployer key on construction.
        if (vm.envOr("DEPLOYER_KEY", uint256(0)) == 0) vm.setEnv("DEPLOYER_KEY", vm.toString(uint256(1)));
        deploy = new DeployHarness();

        // The script creates the repo with itself as the initial maintainer.
        repo = PluginRepo(
            address(
                new ERC1967Proxy(address(new PluginRepo()), abi.encodeCall(PluginRepo.initialize, (address(deploy))))
            )
        );
        setup = new MultisigSetup();
    }

    function _setupOf(uint16 _build) internal view returns (address) {
        return repo.getVersion(PluginRepo.Tag(PluginSettings.VERSION_RELEASE, _build)).pluginSetup;
    }

    function test_WhenPublishingOnAnEmptyRepo() external {
        // it should publish placeholders on builds 1 to VERSION_BUILD - 1.
        // it should publish the setup as VERSION_BUILD, with the given metadata.
        deploy.exposed_publish(repo, address(setup), BUILD_METADATA, RELEASE_METADATA);

        assertEq(repo.latestRelease(), PluginSettings.VERSION_RELEASE, "release");
        assertEq(repo.buildCount(PluginSettings.VERSION_RELEASE), PluginSettings.VERSION_BUILD, "builds");
        assertEq(_setupOf(PluginSettings.VERSION_BUILD), address(setup), "setup");
        assertEq(
            repo.getVersion(PluginRepo.Tag(PluginSettings.VERSION_RELEASE, PluginSettings.VERSION_BUILD)).buildMetadata,
            BUILD_METADATA,
            "build metadata"
        );
        assertEq(repo.getLatestVersion(address(setup)).tag.build, PluginSettings.VERSION_BUILD, "latest for setup");

        address placeholder = address(deploy.placeholderSetup());
        assertTrue(placeholder != address(0) || PluginSettings.VERSION_BUILD == 1, "placeholder deployed");
        for (uint16 b = 1; b < PluginSettings.VERSION_BUILD; ++b) {
            assertEq(_setupOf(b), placeholder, "placeholder build");
            assertEq(
                repo.getVersion(PluginRepo.Tag(PluginSettings.VERSION_RELEASE, b)).buildMetadata,
                bytes(PluginSettings.PLACEHOLDER_BUILD_METADATA),
                "placeholder metadata"
            );
        }
    }

    function test_WhenPublished_PlaceholderBuildsHaveNoPlugin() external {
        // it should not leave the real setup reachable from a placeholder build.
        deploy.exposed_publish(repo, address(setup), BUILD_METADATA, RELEASE_METADATA);
        for (uint16 b = 1; b < PluginSettings.VERSION_BUILD; ++b) {
            assertTrue(_setupOf(b) != address(setup), "placeholder builds never point to the real setup");
            assertTrue(PlaceholderSetup(_setupOf(b)).implementation() == address(0), "placeholder has no plugin");
        }
    }

    function test_RevertWhen_TheRepoAlreadyHasBuilds() external {
        // it should revert, Deploy is only for brand new repos (use NewVersion otherwise).
        deploy.exposed_publish(repo, address(setup), BUILD_METADATA, RELEASE_METADATA);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseScript.InvalidVersionBuild.selector, PluginSettings.VERSION_BUILD, PluginSettings.VERSION_BUILD
            )
        );
        deploy.exposed_publish(repo, address(setup), BUILD_METADATA, RELEASE_METADATA);
    }

    function test_RevertWhen_ReleaseMetadataIsEmpty() external {
        // it should revert, a new release needs release metadata.
        vm.expectRevert(PluginRepo.EmptyReleaseMetadata.selector);
        deploy.exposed_publish(repo, address(setup), BUILD_METADATA, "");
    }

    function test_WhenTransferringOwnership() external {
        // it should give ROOT, MAINTAINER and UPGRADE_REPO to the management DAO.
        // it should leave the deployer with none of them.
        bytes32[3] memory ids =
            [repo.ROOT_PERMISSION_ID(), repo.MAINTAINER_PERMISSION_ID(), repo.UPGRADE_REPO_PERMISSION_ID()];
        for (uint256 i; i < 3; ++i) {
            assertTrue(repo.isGranted(address(repo), address(deploy), ids[i], ""), "deployer before");
        }

        deploy.exposed_transferOwnership(repo, managementDao, address(deploy));

        for (uint256 i; i < 3; ++i) {
            assertTrue(repo.isGranted(address(repo), managementDao, ids[i], ""), "management DAO");
            assertFalse(repo.isGranted(address(repo), address(deploy), ids[i], ""), "deployer after");
        }

        // and the deployer can no longer publish.
        vm.expectRevert();
        deploy.exposed_publish(repo, address(setup), BUILD_METADATA, RELEASE_METADATA);
    }

    function test_WhenMetadataIsNotPinned() external {
        // it should refuse to run until every metadata constant is set.
        if (bytes(PluginSettings.BUILD_METADATA).length == 0) {
            vm.expectRevert(abi.encodeWithSelector(BaseScript.MetadataNotPinned.selector, "BUILD_METADATA"));
        } else if (bytes(PluginSettings.RELEASE_METADATA).length == 0) {
            vm.expectRevert(abi.encodeWithSelector(BaseScript.MetadataNotPinned.selector, "RELEASE_METADATA"));
        } else if (bytes(PluginSettings.PROPOSAL_METADATA).length == 0) {
            vm.expectRevert(abi.encodeWithSelector(BaseScript.MetadataNotPinned.selector, "PROPOSAL_METADATA"));
        }
        deploy.exposed_requireMetadata();
    }

    function test_WhenMetadataIsPinned_ItIsAnIpfsUri() external view {
        // it should only hold ipfs:// URIs (or nothing yet).
        string[3] memory values =
            [PluginSettings.BUILD_METADATA, PluginSettings.RELEASE_METADATA, PluginSettings.PROPOSAL_METADATA];
        for (uint256 i; i < 3; ++i) {
            if (bytes(values[i]).length == 0) continue;
            assertGt(bytes(values[i]).length, 7, "uri length");
            assertEq(vm.indexOf(values[i], "ipfs://"), 0, "ipfs scheme");
        }
        assertEq(vm.indexOf(PluginSettings.PLACEHOLDER_BUILD_METADATA, "ipfs://"), 0, "placeholder");
    }

    /// @dev One test on purpose: `vm.setEnv` is process-wide and tests run in parallel.
    function test_WhenReadingTheEnsSubdomain() external {
        // it should use no ENS name when unset or empty (the registry skips ENS for an empty subdomain).
        // it should use the configured subdomain as is.
        vm.setEnv("MULTISIG_ENS_SUBDOMAIN", "");
        assertEq(deploy.exposed_ensSubdomain(), "", "empty");
        vm.setEnv("MULTISIG_ENS_SUBDOMAIN", "multisig");
        assertEq(deploy.exposed_ensSubdomain(), "multisig", "subdomain");
        vm.setEnv("MULTISIG_ENS_SUBDOMAIN", "");
    }

    /// @dev One test on purpose: `vm.setEnv` (NETWORK_NAME, SIMULATION) is process-wide and tests run in parallel.
    function test_WhenWritingTheArtifact() external {
        // it should write nothing during a dry run (SIMULATION).
        // it should record every published build: placeholders flagged, without implementation or current;
        // the real build last, with its implementation and current.
        vm.setEnv("NETWORK_NAME", "unit-test");
        deploy.exposed_publish(repo, address(setup), BUILD_METADATA, RELEASE_METADATA);
        string memory path =
            string.concat(vm.projectRoot(), "/artifacts/artifacts-unit-test-", vm.toString(block.timestamp), ".json");

        vm.setEnv("SIMULATION", "true");
        deploy.exposed_writeArtifact(repo, managementDao, deploy.exposed_publishedVersions(address(setup)));
        assertFalse(vm.exists(path), "no artifact in a simulation");

        vm.setEnv("SIMULATION", "false");
        deploy.exposed_writeArtifact(repo, managementDao, deploy.exposed_publishedVersions(address(setup)));
        string memory json = vm.readFile(path);
        vm.removeFile(path);

        assertEq(vm.parseJsonUint(json, ".chainId"), block.chainid, "chainId");
        assertEq(vm.parseJsonString(json, ".network"), "unit-test", "network");
        assertEq(vm.parseJsonString(json, ".slug"), "multisig", "slug");
        assertEq(vm.parseJsonAddress(json, ".plugin.repo"), address(repo), "repo");
        assertEq(vm.parseJsonString(json, ".plugin.ens"), "multisig.plugin.dao.eth", "ens");
        assertEq(vm.parseJsonAddress(json, ".plugin.maintainer"), managementDao, "maintainer");

        for (uint16 b = 1; b <= PluginSettings.VERSION_BUILD; ++b) {
            string memory v = string.concat(".plugin.versions[", vm.toString(uint256(b - 1)), "]");
            assertEq(vm.parseJsonUint(json, string.concat(v, ".release")), PluginSettings.VERSION_RELEASE, "release");
            assertEq(vm.parseJsonUint(json, string.concat(v, ".build")), b, "build");
            assertEq(vm.parseJsonAddress(json, string.concat(v, ".setup")), _setupOf(b), "setup as published");
            if (b < PluginSettings.VERSION_BUILD) {
                assertTrue(vm.parseJsonBool(json, string.concat(v, ".placeholder")), "placeholder flag");
                assertFalse(vm.keyExistsJson(json, string.concat(v, ".implementation")), "no implementation");
                assertFalse(vm.keyExistsJson(json, string.concat(v, ".current")), "never current");
            } else {
                assertFalse(vm.keyExistsJson(json, string.concat(v, ".placeholder")), "not a placeholder");
                assertEq(
                    vm.parseJsonAddress(json, string.concat(v, ".implementation")),
                    setup.implementation(),
                    "implementation"
                );
                assertTrue(vm.parseJsonBool(json, string.concat(v, ".current")), "current");
            }
        }
        assertFalse(
            vm.keyExistsJson(
                json, string.concat(".plugin.versions[", vm.toString(uint256(PluginSettings.VERSION_BUILD)), "]")
            ),
            "nothing else"
        );
    }
}
