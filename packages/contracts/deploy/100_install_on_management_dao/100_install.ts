import {PLUGIN_REPO_ENS_SUBDOMAIN_NAME} from '../../plugin-settings';
import {VERSION, METADATA} from '../../plugin-settings';
import {
  AragonOSxAsciiArt,
  getProductionNetworkName,
  isLocal,
  getManagementDao,
  isValidAddress,
  getLatestContractAddress,
  findPluginRepo,
} from '../../utils/helpers';
import {getNetworkByNameOrAlias} from '@aragon/osx-commons-configs';
import {
  UnsupportedNetworkError,
  getNamedTypesFromMetadata,
  findEvent,
} from '@aragon/osx-commons-sdk';
import {
  DAO,
  DAO__factory,
  ENSSubdomainRegistrar__factory,
  ENS__factory,
  IAddrResolver__factory,
  PluginRepo,
  PluginRepoEvents,
  PluginRepoFactory,
  PluginRepo__factory,
  PluginRepoFactory__factory,
  PluginRepoRegistry__factory,
  PluginSetupProcessor__factory,
  PluginSetupProcessorEvents,
} from '@aragon/osx-ethers';
import {defaultAbiCoder, keccak256} from 'ethers/lib/utils';
import {DeployFunction} from 'hardhat-deploy/types';
import {HardhatRuntimeEnvironment} from 'hardhat/types';
import path from 'path';

/**
 * Prints information about the used/forked network and initial deployer wallet balance.
 * @param {HardhatRuntimeEnvironment} hre
 */
const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  console.log(`\n✨ Install on Management DAO:`);
  const {ethers, network} = hre;

  const [deployer] = await hre.ethers.getSigners();

  if (network.name !== 'localhost' && network.name !== 'hardhat') {
    if (
      !('MANAGINGDAO_MULTISIG_LISTEDONLY' in process.env) ||
      !('MANAGINGDAO_MULTISIG_MINAPPROVALS' in process.env) ||
      !('MANAGINGDAO_MULTISIG_APPROVERS' in process.env)
    ) {
      throw new Error('Managing DAO Multisig settings not set in .env');
    }
  }

  const approvers = process.env.MANAGINGDAO_MULTISIG_APPROVERS?.split(',') || [
    deployer.address,
  ];
  const minApprovals = parseInt(
    process.env.MANAGINGDAO_MULTISIG_MINAPPROVALS || '1'
  );
  // In case `MANAGINGDAO_MULTISIG_LISTEDONLY` not present in .env
  // which applies only hardhat/localhost, use `true` setting for extra safety for tests.
  const listedOnly =
    'MANAGINGDAO_MULTISIG_LISTEDONLY' in process.env
      ? process.env.MANAGINGDAO_MULTISIG_LISTEDONLY === 'true'
      : true;

  // Get `managingDAO` address.
  const managingDAO = await getManagementDao(hre);

  // Get `PluginSetupProcessor` from env vars or commons config deployment
  let pspAddress;

  if (process.env.PLUGIN_SETUP_PROCESSOR_ADDRESS) {
    pspAddress = process.env.PLUGIN_SETUP_PROCESSOR_ADDRESS;
    // getting the psp from the env var
    if (!isValidAddress(pspAddress)) {
      throw new Error(
        'PluginSetupProcessor address in .env is not valid address (is not an address or is address zero)'
      );
    }

    // psp = PluginSetupProcessor__factory.connect(pspAddress, deployer);
  } else {
    pspAddress = await getLatestContractAddress('PluginSetupProcessor', hre);
  }

  // Get `PluginSetupProcessor` contract.
  const pspContract = PluginSetupProcessor__factory.connect(
    pspAddress,
    deployer
  );

  // Install latest multisig version
  const {pluginRepo: multisigRepo} = await findPluginRepo(hre);
  if (!multisigRepo) {
    throw new Error('Multisig repo not found');
  }
  const multisigSetupRepoAddress = (
    await multisigRepo['getLatestVersion(uint8)'](VERSION.release)
  ).pluginSetup;

  const pluginSetupRef = {
    pluginSetupRepo: multisigSetupRepoAddress,
    versionTag: VERSION,
  };

  // Prepare multisig plugin for managingDAO
  const data = ethers.utils.defaultAbiCoder.encode(
    getNamedTypesFromMetadata(
      METADATA.build.pluginSetup.prepareInstallation.inputs
    ),
    [approvers, [listedOnly, minApprovals]]
  );
  const prepareTx = await pspContract.prepareInstallation(managingDAO.address, {
    data,
    pluginSetupRef,
  });
  await prepareTx.wait();

  // extract info from prepare event
  const event =
    await findEvent<PluginSetupProcessorEvents.InstallationPreparedEvent>(
      prepareTx,
      'InstallationPrepared'
    );
  const installationPreparedEvent = event.args;

  // hre.managingDAOMultisigPluginAddress = installationPreparedEvent.plugin;

  console.log(
    `Prepared (Multisig: ${installationPreparedEvent.plugin} version (release: ${VERSION.release} / build: ${VERSION.build}) to be applied on (ManagingDAO: ${managingDAO.address}), see (tx: ${prepareTx.hash})`
  );

  // Apply multisig plugin to the managingDAO
  const applyTx = await pspContract.applyInstallation(managingDAO.address, {
    helpersHash: hashHelpers(
      installationPreparedEvent.preparedSetupData.helpers
    ),
    permissions: installationPreparedEvent.preparedSetupData.permissions,
    plugin: installationPreparedEvent.plugin,
    pluginSetupRef,
  });
  await applyTx.wait();

  // todo check permission
  // await checkPermission(managingDaoContract, {
  //   operation: Operation.Grant,
  //   where: {name: 'ManagingDAO', address: managingDAOAddress},
  //   who: {name: 'Multisig plugin', address: installationPreparedEvent.plugin},
  //   permission: 'EXECUTE_PERMISSION',
  // });

  console.log(
    `Applied (Multisig: ${installationPreparedEvent.plugin}) on (ManagingDAO: ${managingDAO.address}), see (tx: ${applyTx.hash})`
  );
};

export default func;
func.tags = ['InstallOnManagementDao'];

export function hashHelpers(helpers: string[]) {
  return keccak256(defaultAbiCoder.encode(['address[]'], [helpers]));
}
