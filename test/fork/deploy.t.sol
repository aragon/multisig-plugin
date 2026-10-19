// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {ENS} from "@ensdomains/ens-contracts/contracts/registry/ENS.sol";
import {AddrResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/AddrResolver.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {ENSSubdomainRegistrar} from "@aragon/osx/framework/utils/ens/ENSSubdomainRegistrar.sol";

import {MultisigSetup} from "../../src/MultisigSetup.sol";
import {PluginSettings} from "../../script/PluginSettings.sol";
import {DeployHarness} from "../utils/harness/DeployHarness.sol";
import {ForkBaseTest} from "./ForkBaseTest.t.sol";

/// @dev The steps of `Deploy.s.sol` against the live PluginRepoFactory and ENS. The full `run()` refuses to
///      run until the metadata is pinned (`MetadataNotPinned`), so the steps are called one by one.
contract Deploy_ForkTest is ForkBaseTest {
    DeployHarness internal deploy;
    PluginRepoFactory internal factory;

    function setUp() public override {
        super.setUp();
        if (vm.envOr("DEPLOYER_KEY", uint256(0)) == 0) vm.setEnv("DEPLOYER_KEY", vm.toString(uint256(1)));
        deploy = new DeployHarness();
        factory = PluginRepoFactory(vm.envAddress("PLUGIN_REPO_FACTORY_ADDRESS"));
    }

    function test_WhenDeployingANewRepo() external {
        // it should register the repo and its ENS subdomain, publish the builds and hand it to the management DAO.
        string memory subdomain = string.concat("multisig-fork-", vm.toString(block.timestamp));
        vm.prank(address(deploy));
        PluginRepo repo = factory.createPluginRepo(subdomain, address(deploy));
        MultisigSetup setup = new MultisigSetup();

        deploy.exposed_publish(repo, address(setup), "ipfs://build", "ipfs://release");
        deploy.exposed_transferOwnership(repo, managementDao, address(deploy));

        // registry and ENS
        assertTrue(factory.pluginRepoRegistry().entries(address(repo)), "registered");
        ENSSubdomainRegistrar registrar = factory.pluginRepoRegistry().subdomainRegistrar();
        bytes32 node = keccak256(abi.encodePacked(registrar.node(), keccak256(bytes(subdomain))));
        address resolver = ENS(registrar.ens()).resolver(node);
        assertEq(AddrResolver(resolver).addr(node), address(repo), "ENS resolves to the repo");

        // versions
        assertEq(repo.buildCount(PluginSettings.VERSION_RELEASE), PluginSettings.VERSION_BUILD, "builds");
        assertEq(
            repo.getLatestVersion(PluginSettings.VERSION_RELEASE).pluginSetup, address(setup), "latest is the setup"
        );

        // ownership
        bytes32[3] memory ids =
            [repo.ROOT_PERMISSION_ID(), repo.MAINTAINER_PERMISSION_ID(), repo.UPGRADE_REPO_PERMISSION_ID()];
        for (uint256 i; i < 3; ++i) {
            assertTrue(repo.isGranted(address(repo), managementDao, ids[i], ""), "management DAO");
            assertFalse(repo.isGranted(address(repo), address(deploy), ids[i], ""), "deployer");
        }
    }

    function test_WhenDeployingWithoutAnEnsSubdomain() external {
        // it should register the repo without creating any ENS record.
        address ens = address(factory.pluginRepoRegistry().subdomainRegistrar().ens());
        vm.recordLogs();
        vm.prank(address(deploy));
        PluginRepo repo = factory.createPluginRepo("", address(deploy));

        assertTrue(factory.pluginRepoRegistry().entries(address(repo)), "registered");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].emitter != ens, "no ENS registry event");
        }
    }

    function test_RevertWhen_TheSubdomainIsTaken() external {
        // it should revert: the canonical name already points to the live repo.
        vm.prank(address(deploy));
        vm.expectRevert();
        factory.createPluginRepo("multisig", address(deploy));
    }
}
