import {METADATA, VERSION} from '../../plugin-settings';
import {
  IPlugin,
  PluginUpgradeableSetup__factory,
  ProxyFactory__factory,
} from '../../typechain';
import {PluginUUPSUpgradeable__factory} from '../../typechain/factories/@aragon/osx-v1.0.0/core/plugin';
import {latestPluginBuild} from '../multisig-constants';
import {ARTIFACT_SOURCES} from '../test-utils/wrapper';
import {
  DAO_PERMISSIONS,
  PLUGIN_SETUP_PROCESSOR_PERMISSIONS,
  PLUGIN_UUPS_UPGRADEABLE_PERMISSIONS,
  findEvent,
  getNamedTypesFromMetadata,
} from '@aragon/osx-commons-sdk';
import {
  PluginSetupProcessorEvents,
  PluginSetupProcessorStructs,
  PluginSetupProcessor,
  DAOStructs,
  DAO,
  DAO__factory,
  PluginRepo,
} from '@aragon/osx-ethers';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {expect} from 'chai';
import {ContractTransaction} from 'ethers';
import hre, {ethers} from 'hardhat';

const OZ_INITIALIZED_SLOT_POSITION = 0;

export async function installPLugin(
  signer: SignerWithAddress,
  psp: PluginSetupProcessor,
  dao: DAO,
  pluginSetupRef: PluginSetupProcessorStructs.PluginSetupRefStruct,
  data: string
): Promise<{
  prepareTx: ContractTransaction;
  applyTx: ContractTransaction;
  preparedEvent: PluginSetupProcessorEvents.InstallationPreparedEvent;
  appliedEvent: PluginSetupProcessorEvents.InstallationAppliedEvent;
}> {
  const prepareTx = await psp.connect(signer).prepareInstallation(dao.address, {
    pluginSetupRef: pluginSetupRef,
    data: data,
  });

  const preparedEvent =
    findEvent<PluginSetupProcessorEvents.InstallationPreparedEvent>(
      await prepareTx.wait(),
      psp.interface.getEvent('InstallationPrepared').name
    );

  const plugin = preparedEvent.args.plugin;
  const preparedPermissions = preparedEvent.args.preparedSetupData.permissions;

  await checkPermissions(
    preparedPermissions,
    dao,
    psp,
    signer,
    PLUGIN_SETUP_PROCESSOR_PERMISSIONS.APPLY_INSTALLATION_PERMISSION_ID
  );

  const applyTx = await psp.connect(signer).applyInstallation(dao.address, {
    pluginSetupRef: pluginSetupRef,
    plugin: plugin,
    permissions: preparedPermissions,
    helpersHash: ethers.utils.keccak256(
      ethers.utils.defaultAbiCoder.encode(
        ['address[]'],
        [preparedEvent.args.preparedSetupData.helpers]
      )
    ),
  });

  const appliedEvent =
    findEvent<PluginSetupProcessorEvents.InstallationAppliedEvent>(
      await applyTx.wait(),
      psp.interface.getEvent('InstallationApplied').name
    );

  return {prepareTx, applyTx, preparedEvent, appliedEvent};
}

export async function uninstallPLugin(
  signer: SignerWithAddress,
  psp: PluginSetupProcessor,
  dao: DAO,
  plugin: IPlugin,
  pluginSetupRef: PluginSetupProcessorStructs.PluginSetupRefStruct,
  data: string,
  currentHelpers: string[]
): Promise<{
  prepareTx: ContractTransaction;
  applyTx: ContractTransaction;
  preparedEvent: PluginSetupProcessorEvents.UninstallationPreparedEvent;
  appliedEvent: PluginSetupProcessorEvents.UninstallationAppliedEvent;
}> {
  const prepareTx = await psp
    .connect(signer)
    .prepareUninstallation(dao.address, {
      pluginSetupRef: pluginSetupRef,
      setupPayload: {
        plugin: plugin.address,
        currentHelpers: currentHelpers,
        data: data,
      },
    });

  const preparedEvent =
    await findEvent<PluginSetupProcessorEvents.UninstallationPreparedEvent>(
      await prepareTx.wait(),
      psp.interface.getEvent('UninstallationPrepared').name
    );

  const preparedPermissions = preparedEvent.args.permissions;

  await checkPermissions(
    preparedPermissions,
    dao,
    psp,
    signer,
    PLUGIN_SETUP_PROCESSOR_PERMISSIONS.APPLY_UNINSTALLATION_PERMISSION_ID
  );

  const applyTx = await psp.connect(signer).applyUninstallation(dao.address, {
    plugin: plugin.address,
    pluginSetupRef: pluginSetupRef,
    permissions: preparedPermissions,
  });

  const appliedEvent =
    findEvent<PluginSetupProcessorEvents.UninstallationAppliedEvent>(
      await applyTx.wait(),
      psp.interface.getEvent('UninstallationApplied').name
    );

  return {prepareTx, applyTx, preparedEvent, appliedEvent};
}
export async function updatePlugin(
  signer: SignerWithAddress,
  psp: PluginSetupProcessor,
  dao: DAO,
  plugin: IPlugin,
  currentHelpers: string[],
  pluginSetupRefCurrent: PluginSetupProcessorStructs.PluginSetupRefStruct,
  pluginSetupRefUpdate: PluginSetupProcessorStructs.PluginSetupRefStruct,
  data: string
): Promise<{
  prepareTx: ContractTransaction;
  applyTx: ContractTransaction;
  preparedEvent: PluginSetupProcessorEvents.UpdatePreparedEvent;
  appliedEvent: PluginSetupProcessorEvents.UpdateAppliedEvent;
}> {
  expect(pluginSetupRefCurrent.pluginSetupRepo).to.equal(
    pluginSetupRefUpdate.pluginSetupRepo
  );

  const prepareTx = await psp.connect(signer).prepareUpdate(dao.address, {
    currentVersionTag: pluginSetupRefCurrent.versionTag,
    newVersionTag: pluginSetupRefUpdate.versionTag,
    pluginSetupRepo: pluginSetupRefUpdate.pluginSetupRepo,
    setupPayload: {
      plugin: plugin.address,
      currentHelpers: currentHelpers,
      data: data,
    },
  });
  const preparedEvent =
    findEvent<PluginSetupProcessorEvents.UpdatePreparedEvent>(
      await prepareTx.wait(),
      psp.interface.getEvent('UpdatePrepared').name
    );

  const preparedPermissions = preparedEvent.args.preparedSetupData.permissions;

  await checkPermissions(
    preparedPermissions,
    dao,
    psp,
    signer,
    PLUGIN_SETUP_PROCESSOR_PERMISSIONS.APPLY_UPDATE_PERMISSION_ID
  );

  const applyTx = await psp.connect(signer).applyUpdate(dao.address, {
    plugin: plugin.address,
    pluginSetupRef: pluginSetupRefUpdate,
    initData: preparedEvent.args.initData,
    permissions: preparedPermissions,
    helpersHash: ethers.utils.keccak256(
      ethers.utils.defaultAbiCoder.encode(
        ['address[]'],
        [preparedEvent.args.preparedSetupData.helpers]
      )
    ),
  });
  const appliedEvent = findEvent<PluginSetupProcessorEvents.UpdateAppliedEvent>(
    await applyTx.wait(),
    psp.interface.getEvent('UpdateApplied').name
  );

  return {prepareTx, applyTx, preparedEvent, appliedEvent};
}

async function checkPermissions(
  preparedPermissions: DAOStructs.MultiTargetPermissionStruct[],
  dao: DAO,
  psp: PluginSetupProcessor,
  signer: SignerWithAddress,
  applyPermissionId: string
) {
  if (preparedPermissions.length !== 0) {
    if (
      !(await dao.hasPermission(
        dao.address,
        psp.address,
        DAO_PERMISSIONS.ROOT_PERMISSION_ID,
        []
      ))
    ) {
      throw `The 'PluginSetupProcessor' does not have 'ROOT_PERMISSION_ID' on the DAO and thus cannot process the list of permissions requested by the plugin setup.`;
    }
  }
  if (
    signer.address !== dao.address &&
    !(await dao.hasPermission(
      psp.address,
      signer.address,
      applyPermissionId,
      []
    ))
  ) {
    throw `The used signer does not have the permission with ID '${applyPermissionId}' granted and thus cannot apply the setup`;
  }
}

export async function updateFromBuildTest(
  dao: DAO,
  deployer: SignerWithAddress,
  psp: PluginSetupProcessor,
  pluginRepo: PluginRepo,
  pluginSetupRefLatestBuild: PluginSetupProcessorStructs.PluginSetupRefStruct,
  build: number,
  installationInputs: any[],
  updateInputs: any[],
  reinitializedVersion: number
) {
  // Grant deployer all required permissions
  await dao
    .connect(deployer)
    .grant(
      psp.address,
      deployer.address,
      PLUGIN_SETUP_PROCESSOR_PERMISSIONS.APPLY_INSTALLATION_PERMISSION_ID
    );
  await dao
    .connect(deployer)
    .grant(
      psp.address,
      deployer.address,
      PLUGIN_SETUP_PROCESSOR_PERMISSIONS.APPLY_UPDATE_PERMISSION_ID
    );

  await dao
    .connect(deployer)
    .grant(dao.address, psp.address, DAO_PERMISSIONS.ROOT_PERMISSION_ID);

  // Install a previous build with build number `build`
  const pluginSetupRefPreviousBuild = {
    versionTag: {
      release: VERSION.release,
      build: build,
    },
    pluginSetupRepo: pluginRepo.address,
  };

  const installationResults = await installPLugin(
    deployer,
    psp,
    dao,
    pluginSetupRefPreviousBuild,
    ethers.utils.defaultAbiCoder.encode(
      getNamedTypesFromMetadata(
        // NOTE that this approach is not efficient and in reality, we should be
        // fetching `build`'s ipfs cid from pluginRepo and getting the abi from there.
        [
          METADATA.build.pluginSetup.prepareInstallation.inputs[0],
          METADATA.build.pluginSetup.prepareInstallation.inputs[1],
        ]
      ),
      installationInputs
    )
  );

  // Get the plugin address.
  const plugin = PluginUUPSUpgradeable__factory.connect(
    installationResults.preparedEvent.args.plugin,
    deployer
  );

  // Check that the implementation of the plugin proxy matches the latest build
  const implementationPreviousBuild =
    await PluginUpgradeableSetup__factory.connect(
      (
        await pluginRepo['getVersion((uint8,uint16))'](
          pluginSetupRefPreviousBuild.versionTag
        )
      ).pluginSetup,
      deployer
    ).implementation();
  expect(await plugin.implementation()).to.equal(implementationPreviousBuild);

  // Grant the PSP the permission to upgrade the plugin implementation.
  await dao
    .connect(deployer)
    .grant(
      plugin.address,
      psp.address,
      PLUGIN_UUPS_UPGRADEABLE_PERMISSIONS.UPGRADE_PLUGIN_PERMISSION_ID
    );

  // Update from the previous build to the latest build
  await expect(
    updatePlugin(
      deployer,
      psp,
      dao,
      plugin,
      installationResults.preparedEvent.args.preparedSetupData.helpers,
      pluginSetupRefPreviousBuild,
      pluginSetupRefLatestBuild,
      ethers.utils.defaultAbiCoder.encode(
        getNamedTypesFromMetadata(
          METADATA.build.pluginSetup.prepareUpdate[latestPluginBuild].inputs
        ),
        updateInputs
      )
    )
  ).to.not.be.reverted;

  // Check that the implementation of the plugin proxy matches the latest build
  const implementationLatestBuild =
    await PluginUpgradeableSetup__factory.connect(
      (
        await pluginRepo['getVersion((uint8,uint16))'](
          pluginSetupRefLatestBuild.versionTag
        )
      ).pluginSetup,
      deployer
    ).implementation();
  expect(await plugin.implementation()).to.equal(implementationLatestBuild);

  // check the plugin was reinitialized, OZs `_initialized` at storage slot [0] is correct
  expect(
    ethers.BigNumber.from(
      await ethers.provider.getStorageAt(
        plugin.address,
        OZ_INITIALIZED_SLOT_POSITION
      )
    ).toNumber()
  ).to.equal(reinitializedVersion);
}

export async function createDaoProxy(
  deployer: SignerWithAddress,
  dummyMetadata: string
): Promise<DAO> {
  const dao = await hre.wrapper.deploy(ARTIFACT_SOURCES.DAO, {
    withProxy: true,
    initArgs: [
      dummyMetadata,
      deployer.address,
      ethers.constants.AddressZero,
      dummyMetadata,
    ],
    proxySettings: {
      initializer: 'initialize',
    },
  });

  return dao;
}
