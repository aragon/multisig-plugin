// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../BaseTest.t.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {PlaceholderSetup} from "@aragon/osx/framework/plugin/repo/placeholder/PlaceholderSetup.sol";
import {ENSSubdomainRegistrar} from "@aragon/osx/framework/utils/ens/ENSSubdomainRegistrar.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginSetupRef, hashHelpers} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {DAOMock} from "../../../../lib/osx/test/mocks/commons/dao/DAOMock.sol";

import {Multisig} from "../../../../src/Multisig.sol";
import {MultisigSetup} from "../../../../src/MultisigSetup.sol";
import {ListedCheckCondition} from "../../../../src/ListedCheckCondition.sol";

/// @notice Install, use, update and uninstall the plugin through a real, locally deployed PluginSetupProcessor.
/// @dev The repo mirrors production numbering: builds 1 and 2 are placeholders (the legacy builds cannot be
///      compiled here), build 3 is the current code, build 4 is a fresh deployment of the same code (real
///      upgrade path) and build 5 republishes build 4's setup (UI-only update path).
contract PluginSetup_Multisig_IntegrationTest is BaseTest {
    bytes32 internal constant APPLY_INSTALLATION_PERMISSION_ID = keccak256("APPLY_INSTALLATION_PERMISSION");
    bytes32 internal constant APPLY_UPDATE_PERMISSION_ID = keccak256("APPLY_UPDATE_PERMISSION");
    bytes32 internal constant APPLY_UNINSTALLATION_PERMISSION_ID = keccak256("APPLY_UNINSTALLATION_PERMISSION");

    PluginSetupProcessor internal psp;
    PluginRepo internal repo;
    MultisigSetup internal setupV3;
    MultisigSetup internal setupV4;

    function setUp() public override {
        super.setUp();

        // Framework without ENS: an allow-all managing DAO and no subdomain registrar.
        DAOMock managingDao = new DAOMock();
        managingDao.setHasPermissionReturnValueMock(true);
        PluginRepoRegistry registry = PluginRepoRegistry(
            address(
                new ERC1967Proxy(
                    address(new PluginRepoRegistry()),
                    abi.encodeCall(
                        PluginRepoRegistry.initialize, (IDAO(address(managingDao)), ENSSubdomainRegistrar(address(0)))
                    )
                )
            )
        );
        psp = new PluginSetupProcessor(registry);
        PluginRepoFactory factory = new PluginRepoFactory(registry);

        PlaceholderSetup placeholder = new PlaceholderSetup();
        setupV3 = new MultisigSetup();
        setupV4 = new MultisigSetup();

        repo = factory.createPluginRepoWithFirstVersion("", address(placeholder), address(this), hex"11", hex"11");
        repo.createVersion(1, address(placeholder), hex"11", "");
        repo.createVersion(1, address(setupV3), hex"33", "");
        repo.createVersion(1, address(setupV4), hex"44", "");
        repo.createVersion(1, address(setupV4), hex"55", "");

        // The applier (manager) may apply setups; the PSP gets ROOT just in time (see `_withPspRoot`).
        _grant(address(psp), manager, APPLY_INSTALLATION_PERMISSION_ID);
        _grant(address(psp), manager, APPLY_UPDATE_PERMISSION_ID);
        _grant(address(psp), manager, APPLY_UNINSTALLATION_PERMISSION_ID);

        vm.label(address(psp), "PSP");
        vm.label(address(repo), "PluginRepo");
    }

    // ==== Helpers ====

    function _ref(uint16 _build) internal view returns (PluginSetupRef memory) {
        return PluginSetupRef({versionTag: PluginRepo.Tag({release: 1, build: _build}), pluginSetupRepo: repo});
    }

    function _install() internal returns (Multisig plugin, address[] memory helpers) {
        bytes memory data = abi.encode(_members(alice, bob, carol), _settings(true, 2), _daoTarget(), PLUGIN_METADATA);
        (address pluginAddress, IPluginSetup.PreparedSetupData memory prepared) = psp.prepareInstallation(
            address(dao), PluginSetupProcessor.PrepareInstallationParams({pluginSetupRef: _ref(3), data: data})
        );

        _grant(address(dao), address(psp), ROOT_PERMISSION_ID);
        vm.prank(manager);
        psp.applyInstallation(
            address(dao),
            PluginSetupProcessor.ApplyInstallationParams({
                pluginSetupRef: _ref(3),
                plugin: pluginAddress,
                permissions: prepared.permissions,
                helpersHash: hashHelpers(prepared.helpers)
            })
        );
        _revoke(address(dao), address(psp), ROOT_PERMISSION_ID);

        return (Multisig(pluginAddress), prepared.helpers);
    }

    function _update(Multisig _plugin, address[] memory _helpers, uint16 _from, uint16 _to)
        internal
        returns (address[] memory newHelpers)
    {
        vm.roll(block.number + 1); // the PSP only applies setups prepared after the last application
        (bytes memory initData, IPluginSetup.PreparedSetupData memory prepared) = psp.prepareUpdate(
            address(dao),
            PluginSetupProcessor.PrepareUpdateParams({
                currentVersionTag: PluginRepo.Tag({release: 1, build: _from}),
                newVersionTag: PluginRepo.Tag({release: 1, build: _to}),
                pluginSetupRepo: repo,
                setupPayload: IPluginSetup.SetupPayload({plugin: address(_plugin), currentHelpers: _helpers, data: ""})
            })
        );

        _grant(address(dao), address(psp), ROOT_PERMISSION_ID);
        _grant(address(_plugin), address(psp), UPGRADE_PLUGIN_PERMISSION_ID);
        vm.prank(manager);
        psp.applyUpdate(
            address(dao),
            PluginSetupProcessor.ApplyUpdateParams({
                plugin: address(_plugin),
                pluginSetupRef: _ref(_to),
                initData: initData,
                permissions: prepared.permissions,
                helpersHash: hashHelpers(prepared.helpers)
            })
        );
        _revoke(address(_plugin), address(psp), UPGRADE_PLUGIN_PERMISSION_ID);
        _revoke(address(dao), address(psp), ROOT_PERMISSION_ID);

        return prepared.helpers;
    }

    function _uninstall(Multisig _plugin, address[] memory _helpers, uint16 _build) internal {
        vm.roll(block.number + 1);
        IPluginSetup.SetupPayload memory payload =
            IPluginSetup.SetupPayload({plugin: address(_plugin), currentHelpers: _helpers, data: ""});
        PermissionLib.MultiTargetPermission[] memory permissions = psp.prepareUninstallation(
            address(dao),
            PluginSetupProcessor.PrepareUninstallationParams({pluginSetupRef: _ref(_build), setupPayload: payload})
        );

        _grant(address(dao), address(psp), ROOT_PERMISSION_ID);
        vm.prank(manager);
        psp.applyUninstallation(
            address(dao),
            PluginSetupProcessor.ApplyUninstallationParams({
                plugin: address(_plugin), pluginSetupRef: _ref(_build), permissions: permissions
            })
        );
        _revoke(address(dao), address(psp), ROOT_PERMISSION_ID);
    }

    function _assertInstalledPermissions(Multisig _plugin) internal view {
        address p = address(_plugin);
        assertTrue(dao.hasPermission(p, address(dao), UPDATE_MULTISIG_SETTINGS_PERMISSION_ID, ""), "settings");
        assertTrue(dao.hasPermission(address(dao), p, EXECUTE_PERMISSION_ID, ""), "execute");
        assertTrue(dao.hasPermission(p, address(dao), SET_TARGET_CONFIG_PERMISSION_ID, ""), "target config");
        assertTrue(dao.hasPermission(p, address(dao), SET_METADATA_PERMISSION_ID, ""), "metadata");
        assertTrue(dao.hasPermission(p, alice, CREATE_PROPOSAL_PERMISSION_ID, ""), "create: member");
        assertFalse(dao.hasPermission(p, dave, CREATE_PROPOSAL_PERMISSION_ID, ""), "create: non member");
        assertTrue(dao.hasPermission(p, dave, EXECUTE_PROPOSAL_PERMISSION_ID, ""), "execute proposal: anyone");
        assertFalse(dao.hasPermission(p, address(dao), UPGRADE_PLUGIN_PERMISSION_ID, ""), "no upgrade permission");
        // Nothing beyond the setup's list was granted to random callers.
        assertFalse(dao.hasPermission(p, dave, UPDATE_MULTISIG_SETTINGS_PERMISSION_ID, ""), "settings: dave");
        assertFalse(dao.hasPermission(address(dao), dave, EXECUTE_PERMISSION_ID, ""), "execute: dave");
    }

    function _assertUninstalledPermissions(Multisig _plugin) internal view {
        address p = address(_plugin);
        assertFalse(dao.hasPermission(p, address(dao), UPDATE_MULTISIG_SETTINGS_PERMISSION_ID, ""), "settings");
        assertFalse(dao.hasPermission(address(dao), p, EXECUTE_PERMISSION_ID, ""), "execute");
        assertFalse(dao.hasPermission(p, address(dao), SET_TARGET_CONFIG_PERMISSION_ID, ""), "target config");
        assertFalse(dao.hasPermission(p, address(dao), SET_METADATA_PERMISSION_ID, ""), "metadata");
        assertFalse(dao.hasPermission(p, alice, CREATE_PROPOSAL_PERMISSION_ID, ""), "create: member");
        assertFalse(dao.hasPermission(p, alice, EXECUTE_PROPOSAL_PERMISSION_ID, ""), "execute proposal");
        assertFalse(dao.hasPermission(address(dao), address(psp), ROOT_PERMISSION_ID, ""), "psp root");
    }

    /// @dev Creates, approves and executes a proposal setting `actionTarget.value` through the DAO.
    function _useEndToEnd(Multisig _plugin, uint256 _value) internal {
        vm.roll(block.number + 1); // creation is forbidden in the block where settings changed
        vm.prank(alice);
        uint256 id = _plugin.createProposal(
            PROPOSAL_METADATA, _valueActions(_value), 0, true, false, 0, uint64(block.timestamp) + PROPOSAL_DURATION
        );
        assertFalse(_plugin.canExecute(id), "not yet executable");

        vm.prank(bob);
        _plugin.approve(id, true);

        (bool executed, uint16 approvals,,,,) = _plugin.getProposal(id);
        assertTrue(executed, "executed");
        assertEq(approvals, 2, "approvals");
        assertEq(actionTarget.value(), _value, "action value");
        assertEq(actionTarget.lastCaller(), address(dao), "executed by the DAO");
    }

    function _valueActions(uint256 _value) internal view returns (Action[] memory actionList) {
        actionList = _actions(1);
        actionList[0].data = abi.encodeWithSignature("setValue(uint256)", _value);
    }

    // ==== Tests ====

    function test_WhenInstallingThroughThePsp() external {
        // it should install the plugin with exactly the setup's permissions.
        // it should leave no ROOT permission to the PSP.
        (Multisig plugin, address[] memory helpers) = _install();

        assertEq(helpers.length, 1, "helpers");
        assertEq(plugin.implementation(), setupV3.implementation(), "implementation");
        assertEq(address(plugin.dao()), address(dao), "dao");
        _assertInstalledPermissions(plugin);
        assertFalse(dao.hasPermission(address(dao), address(psp), ROOT_PERMISSION_ID, ""), "psp root");
    }

    function test_WhenUsingTheInstalledPlugin() external {
        // it should create, approve and execute an action through the DAO.
        (Multisig plugin,) = _install();
        _useEndToEnd(plugin, 42);
    }

    function test_WhenUsingTheInstalledPlugin_ItShouldApplyOnlyListedLive() external {
        // it should let non members create once the DAO turns onlyListed off.
        (Multisig plugin,) = _install();
        vm.prank(address(dao));
        plugin.updateMultisigSettings(_settings(false, 2));
        assertTrue(dao.hasPermission(address(plugin), dave, CREATE_PROPOSAL_PERMISSION_ID, ""), "dave can create");
    }

    function test_WhenUpdatingToANewBuildWithNewCode() external {
        // it should upgrade the proxy to the new implementation with no init data and no permission changes.
        (Multisig plugin, address[] memory helpers) = _install();
        address[] memory newHelpers = _update(plugin, helpers, 3, 4);

        assertEq(plugin.implementation(), setupV4.implementation(), "implementation");
        assertTrue(setupV4.implementation() != setupV3.implementation(), "distinct implementations");
        assertEq(newHelpers.length, 0, "no new helpers");
        _assertInstalledPermissions(plugin);
        // State survives the upgrade.
        assertEq(plugin.addresslistLength(), 3, "members");
        assertEq(plugin.getMetadata(), PLUGIN_METADATA, "metadata");
        _useEndToEnd(plugin, 7);
    }

    function test_RevertWhen_UpdatingWithoutUpgradePermissionForThePsp() external {
        // it should revert: build 3 no longer grants UPGRADE_PLUGIN_PERMISSION, the DAO must grant it temporarily.
        (Multisig plugin, address[] memory helpers) = _install();
        vm.roll(block.number + 1);
        (bytes memory initData, IPluginSetup.PreparedSetupData memory prepared) = psp.prepareUpdate(
            address(dao),
            PluginSetupProcessor.PrepareUpdateParams({
                currentVersionTag: PluginRepo.Tag({release: 1, build: 3}),
                newVersionTag: PluginRepo.Tag({release: 1, build: 4}),
                pluginSetupRepo: repo,
                setupPayload: IPluginSetup.SetupPayload({plugin: address(plugin), currentHelpers: helpers, data: ""})
            })
        );
        _grant(address(dao), address(psp), ROOT_PERMISSION_ID);
        bytes memory expectedError = abi.encodeWithSelector(
            PluginSetupProcessor.PluginProxyUpgradeFailed.selector, address(plugin), setupV4.implementation(), bytes("")
        );
        vm.prank(manager);
        vm.expectRevert(expectedError);
        psp.applyUpdate(
            address(dao),
            PluginSetupProcessor.ApplyUpdateParams({
                plugin: address(plugin),
                pluginSetupRef: _ref(4),
                initData: initData,
                permissions: prepared.permissions,
                helpersHash: hashHelpers(prepared.helpers)
            })
        );
    }

    function test_WhenApplyingAUiOnlyUpdate() external {
        // it should keep the implementation, permissions and helpers.
        (Multisig plugin, address[] memory helpers) = _install();
        address[] memory helpers4 = _update(plugin, helpers, 3, 4);
        address implementation = plugin.implementation();

        address[] memory helpers5 = _update(plugin, helpers4, 4, 5);

        assertEq(plugin.implementation(), implementation, "implementation unchanged");
        assertEq(keccak256(abi.encode(helpers5)), keccak256(abi.encode(helpers4)), "helpers unchanged");
        _assertInstalledPermissions(plugin);
    }

    function test_WhenUninstalling() external {
        // it should revoke every permission granted at installation.
        (Multisig plugin, address[] memory helpers) = _install();
        _uninstall(plugin, helpers, 3);
        _assertUninstalledPermissions(plugin);
    }

    function test_WhenUninstalling_ItShouldStopThePlugin() external {
        // it should make proposal creation and execution impossible.
        (Multisig plugin, address[] memory helpers) = _install();

        vm.roll(block.number + 1);
        vm.prank(alice);
        uint256 id = plugin.createProposal(
            PROPOSAL_METADATA, _valueActions(1), 0, true, false, 0, uint64(block.timestamp) + PROPOSAL_DURATION
        );
        vm.prank(bob);
        plugin.approve(id, false);
        assertTrue(plugin.canExecute(id), "passed before uninstall");

        _uninstall(plugin, helpers, 3);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSignature(
                "DaoUnauthorized(address,address,address,bytes32)",
                address(dao),
                address(plugin),
                alice,
                CREATE_PROPOSAL_PERMISSION_ID
            )
        );
        plugin.createProposal(PROPOSAL_METADATA, _valueActions(2), 0, false, false, 0, uint64(block.timestamp) + 1);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSignature(
                "DaoUnauthorized(address,address,address,bytes32)",
                address(dao),
                address(plugin),
                alice,
                EXECUTE_PROPOSAL_PERMISSION_ID
            )
        );
        plugin.execute(id);
    }

    function test_WhenUninstallingAfterAnUpdate() external {
        // it should leave no permission behind, whatever build was last applied.
        (Multisig plugin, address[] memory helpers) = _install();
        address[] memory helpers4 = _update(plugin, helpers, 3, 4);
        _uninstall(plugin, helpers4, 4);
        _assertUninstalledPermissions(plugin);
    }
}
