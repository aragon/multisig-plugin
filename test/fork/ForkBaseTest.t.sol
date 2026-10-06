// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginSetupRef, hashHelpers} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";

import {Multisig} from "../../src/Multisig.sol";
import {MultisigSetup} from "../../src/MultisigSetup.sol";
import {Constants} from "../utils/Constants.sol";
import {ActionTarget} from "../utils/mocks/ActionTarget.sol";

/// @notice Forks the network selected with `just switch` and uses the live OSx framework and Multisig repo.
/// @dev Run with `just test-fork` (addresses come from just-foundry's `networks/<network>.env`).
///      The code in `src/` is published as the next build of the live repo, as the management DAO would.
contract ForkBaseTest is Constants, Test {
    uint8 internal constant RELEASE = 1;

    PluginRepo internal multisigRepo;
    PluginSetupProcessor internal psp;
    DAOFactory internal daoFactory;
    address internal managementDao;

    /// @dev This repository's code, published on the fork as `localTag`.
    MultisigSetup internal localSetup;
    PluginRepo.Tag internal localTag;
    /// @dev The latest build published on the network before the fork test runs.
    uint16 internal latestPublishedBuild;

    ActionTarget internal actionTarget;
    /// @dev Helpers of the last installation made by `_createDao` (needed by the PSP to update it).
    address[] internal installedHelpers;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("RPC_URL"));

        multisigRepo = PluginRepo(vm.envAddress("MULTISIG_PLUGIN_REPO_ADDRESS"));
        psp = PluginSetupProcessor(vm.envAddress("PLUGIN_SETUP_PROCESSOR_ADDRESS"));
        daoFactory = DAOFactory(vm.envAddress("DAO_FACTORY_ADDRESS"));
        managementDao = vm.envAddress("MANAGEMENT_DAO_ADDRESS");

        latestPublishedBuild = uint16(multisigRepo.buildCount(RELEASE));
        localSetup = new MultisigSetup();
        vm.prank(managementDao);
        multisigRepo.createVersion(RELEASE, address(localSetup), "ipfs://fork-build", "");
        localTag = PluginRepo.Tag({release: RELEASE, build: latestPublishedBuild + 1});

        actionTarget = new ActionTarget();

        vm.label(address(multisigRepo), "MultisigRepo");
        vm.label(address(psp), "PSP");
        vm.label(address(daoFactory), "DAOFactory");
        vm.label(managementDao, "ManagementDAO");
    }

    // ==== DAO creation through the live DAOFactory ====

    function _createDao(PluginRepo.Tag memory _tag, bytes memory _installData)
        internal
        returns (DAO dao, address plugin)
    {
        DAOFactory.PluginSettings[] memory plugins = new DAOFactory.PluginSettings[](1);
        plugins[0] = DAOFactory.PluginSettings({
            pluginSetupRef: PluginSetupRef({versionTag: _tag, pluginSetupRepo: multisigRepo}), data: _installData
        });
        DAOFactory.InstalledPlugin[] memory installed;
        (dao, installed) = daoFactory.createDao(
            DAOFactory.DAOSettings({trustedForwarder: address(0), daoURI: "", subdomain: "", metadata: ""}), plugins
        );
        plugin = installed[0].plugin;
        installedHelpers = installed[0].preparedSetupData.helpers;
        vm.label(address(dao), "DAO");
        vm.label(plugin, "MultisigPlugin");
    }

    /// @dev Installation data of builds 1 and 2 (osx v1.0 and v1.3 Multisig).
    function _legacyInstallData(address[] memory _memberList, uint16 _minApprovals)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(_memberList, Multisig.MultisigSettings({onlyListed: true, minApprovals: _minApprovals}));
    }

    /// @dev Installation data of build 3 and later.
    function _installData(address[] memory _memberList, uint16 _minApprovals) internal pure returns (bytes memory) {
        return abi.encode(
            _memberList,
            Multisig.MultisigSettings({onlyListed: true, minApprovals: _minApprovals}),
            IPlugin.TargetConfig({target: address(0), operation: IPlugin.Operation.Call}),
            bytes("ipfs://fork-plugin-metadata")
        );
    }

    // ==== Update through the live PSP, as a DAO proposal would do it ====

    /// @dev Grants the PSP what it needs (ROOT on the DAO, UPGRADE_PLUGIN on the plugin), prepares and
    ///      applies the update, and revokes both, all as the DAO.
    function _update(
        DAO _dao,
        address _plugin,
        PluginRepo.Tag memory _fromTag,
        address[] memory _currentHelpers,
        bytes memory _updateData
    ) internal returns (IPluginSetup.PreparedSetupData memory, bytes memory) {
        return _update(_dao, _plugin, _fromTag, localTag, _currentHelpers, _updateData);
    }

    function _update(
        DAO _dao,
        address _plugin,
        PluginRepo.Tag memory _fromTag,
        PluginRepo.Tag memory _toTag,
        address[] memory _currentHelpers,
        bytes memory _updateData
    ) internal returns (IPluginSetup.PreparedSetupData memory prepared, bytes memory initData) {
        vm.startPrank(address(_dao));
        _dao.grant(address(_dao), address(psp), ROOT_PERMISSION_ID);
        _dao.grant(_plugin, address(psp), UPGRADE_PLUGIN_PERMISSION_ID);

        (initData, prepared) = psp.prepareUpdate(
            address(_dao),
            PluginSetupProcessor.PrepareUpdateParams({
                currentVersionTag: _fromTag,
                newVersionTag: _toTag,
                pluginSetupRepo: multisigRepo,
                setupPayload: IPluginSetup.SetupPayload({
                    plugin: _plugin, currentHelpers: _currentHelpers, data: _updateData
                })
            })
        );
        psp.applyUpdate(
            address(_dao),
            PluginSetupProcessor.ApplyUpdateParams({
                plugin: _plugin,
                pluginSetupRef: PluginSetupRef({versionTag: _toTag, pluginSetupRepo: multisigRepo}),
                initData: initData,
                permissions: prepared.permissions,
                helpersHash: hashHelpers(prepared.helpers)
            })
        );

        _dao.revoke(address(_dao), address(psp), ROOT_PERMISSION_ID);
        if (_dao.hasPermission(_plugin, address(psp), UPGRADE_PLUGIN_PERMISSION_ID, "")) {
            _dao.revoke(_plugin, address(psp), UPGRADE_PLUGIN_PERMISSION_ID);
        }
        vm.stopPrank();
    }

    // ==== Helpers ====

    function _members() internal view returns (address[] memory list) {
        list = new address[](3);
        list[0] = alice;
        list[1] = bob;
        list[2] = carol;
    }

    function _tag(uint16 _build) internal pure returns (PluginRepo.Tag memory) {
        return PluginRepo.Tag({release: RELEASE, build: _build});
    }
}
