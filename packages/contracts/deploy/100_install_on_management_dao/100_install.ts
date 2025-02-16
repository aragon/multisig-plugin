import {VERSION, METADATA} from '../../plugin-settings';
import {
  getManagementDao,
  isValidAddress,
  getLatestContractAddress,
  findPluginRepo,
  isPermissionSetCorrectly,
} from '../../utils/helpers';
import {
  getNamedTypesFromMetadata,
  findEventTopicLog,
} from '@aragon/osx-commons-sdk';
import {
  DAO_PERMISSIONS,
  Operation,
  PLUGIN_SETUP_PROCESSOR_PERMISSIONS,
} from '@aragon/osx-commons-sdk';
import {
  PluginSetupProcessor__factory,
  PluginSetupProcessorEvents,
  DAOStructs,
} from '@aragon/osx-ethers';
import {defaultAbiCoder, keccak256} from 'ethers/lib/utils';
import {DeployFunction} from 'hardhat-deploy/types';
import {HardhatRuntimeEnvironment} from 'hardhat/types';

/**
 * Prints information about the used/forked network and initial deployer wallet balance.
 * @param {HardhatRuntimeEnvironment} hre
 */
const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {ethers, network} = hre;

  const [deployer] = await hre.ethers.getSigners();

  const approvers = process.env.MANAGEMENT_DAO_MULTISIG_APPROVERS?.split(
    ','
  ) || [deployer.address];
  const minApprovals = parseInt(
    process.env.MANAGEMENT_DAO_MULTISIG_MIN_APPROVALS || '1'
  );

  const listedOnly = process.env.MANAGEMENT_DAO_MULTISIG_LISTED_ONLY;

  // Get `managementDAO` address.
  const managementDAO = await getManagementDao(hre);

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
  } else {
    pspAddress = await getLatestContractAddress('PluginSetupProcessor', hre);
  }

  if (!pspAddress) {
    throw new Error('PluginSetupProcessor address not found');
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

  if (!multisigRepo.address) {
    throw new Error('Multisig repo address not found');
  }

  const pluginSetupRef = {
    pluginSetupRepo: multisigRepo.address,
    versionTag: VERSION,
  };

  // Prepare multisig plugin for managementDAO
  const params = getNamedTypesFromMetadata(
    METADATA.build.pluginSetup.prepareInstallation.inputs
  );

  const data = ethers.utils.defaultAbiCoder.encode(
    [params[0], params[1]],
    [
      approvers,
      [listedOnly, minApprovals],
      [ethers.constants.AddressZero, 0], // [target, operation]
      '0x', // metadata
    ]
  );

  console.log('prepare Installation');
  const prepareTx = await pspContract.prepareInstallation(
    managementDAO.address,
    {
      pluginSetupRef,
      data,
    },
    {
      gasLimit: 30000000,
    }
  );

  // extract info from prepare event
  const event =
    await findEventTopicLog<PluginSetupProcessorEvents.InstallationPreparedEvent>(
      await prepareTx.wait(),
      PluginSetupProcessor__factory.createInterface(),
      'InstallationPrepared'
    );

  const installationPreparedEvent = event.args;

  console.log(
    `Prepared (Multisig: ${installationPreparedEvent.plugin} version (release: ${VERSION.release} / build: ${VERSION.build}) to be applied on (ManagementDAO: ${managementDAO.address}), see (tx: ${prepareTx.hash})`
  );

  // grant
  // ROOT_PERMISSION on the management dao to the PSP
  // APPLY_INSTALLATION_PERMISSION on the PSP to the deployer
  let permissionsToGrant: DAOStructs.MultiTargetPermissionStruct[] = [
    {
      operation: Operation.Grant,
      where: managementDAO.address,
      who: pspAddress,
      condition: ethers.constants.AddressZero,
      permissionId: DAO_PERMISSIONS.ROOT_PERMISSION_ID,
    },
    {
      operation: Operation.Grant,
      where: pspAddress,
      who: deployer.address,
      condition: ethers.constants.AddressZero,
      permissionId:
        PLUGIN_SETUP_PROCESSOR_PERMISSIONS.APPLY_INSTALLATION_PERMISSION_ID,
    },
  ];

  await managementDAO.applyMultiTargetPermissions(permissionsToGrant);

  // Apply multisig plugin to the managementDAO
  const applyTx = await pspContract.applyInstallation(
    managementDAO.address,
    {
      helpersHash: hashHelpers(
        installationPreparedEvent.preparedSetupData.helpers
      ),
      permissions: installationPreparedEvent.preparedSetupData.permissions,
      plugin: installationPreparedEvent.plugin,
      pluginSetupRef,
    },
    {
      gasLimit: 30000000,
    }
  );
  await applyTx.wait();

  const multisigPluginPermission = {
    operation: Operation.Grant,
    where: {name: 'ManagementDAO', address: managementDAO.address},
    who: {name: 'Multisig plugin', address: installationPreparedEvent.plugin},
    permission: 'EXECUTE_PERMISSION',
  };

  const isPermissionCorrect = await isPermissionSetCorrectly(
    managementDAO,
    multisigPluginPermission
  );

  if (!isPermissionCorrect) {
    const {who, where, operation} = multisigPluginPermission;
    if (operation === Operation.Grant) {
      throw new Error(
        `(${who.name}: ${who.address}) doesn't have ${multisigPluginPermission.permission} on (${where.name}: ${where.address}) in ${managementDAO.address}`
      );
    }
    throw new Error(
      `(${who.name}: ${who.address}) has ${multisigPluginPermission.permission} on (${where.name}: ${where.address}) in ${managementDAO.address}`
    );
  }

  console.log(
    `Applied (Multisig: ${installationPreparedEvent.plugin}) on (ManagementDAO: ${managementDAO.address}), see (tx: ${applyTx.hash})`
  );

  // revoke
  // ROOT_PERMISSION permission on the management dao from deployer
  // ROOT_PERMISSION permission on the management dao from psp
  // APPLY_INSTALLATION_PERMISSION permission on the PSP from deployer
  // EXECUTE_PERMISSION permission on the management dao from deployer

  let permissionsToRevoke: DAOStructs.MultiTargetPermissionStruct[] = [
    {
      operation: Operation.Revoke,
      where: managementDAO.address,
      who: deployer.address,
      condition: ethers.constants.AddressZero,
      permissionId: DAO_PERMISSIONS.ROOT_PERMISSION_ID,
    },
    {
      operation: Operation.Revoke,
      where: managementDAO.address,
      who: pspAddress,
      condition: ethers.constants.AddressZero,
      permissionId: DAO_PERMISSIONS.ROOT_PERMISSION_ID,
    },
    {
      operation: Operation.Revoke,
      where: pspAddress,
      who: deployer.address,
      condition: ethers.constants.AddressZero,
      permissionId:
        PLUGIN_SETUP_PROCESSOR_PERMISSIONS.APPLY_INSTALLATION_PERMISSION_ID,
    },
    {
      operation: Operation.Revoke,
      where: managementDAO.address,
      who: deployer.address,
      condition: ethers.constants.AddressZero,
      permissionId: DAO_PERMISSIONS.EXECUTE_PERMISSION_ID,
    },
  ];

  await managementDAO.applyMultiTargetPermissions(permissionsToRevoke);

  console.log('Permissions revoked....');

  // todo check if the permissions are revoked correctly
};

export default func;
func.tags = ['InstallOnManagementDao'];

export function hashHelpers(helpers: string[]) {
  return keccak256(defaultAbiCoder.encode(['address[]'], [helpers]));
}

/**
 * Skips installation if is local network or env vars needed are not defined
 * @param {HardhatRuntimeEnvironment} hre
 */
func.skip = async (hre: HardhatRuntimeEnvironment) => {
  console.log(`\n✨ Install on Management DAO:`);

  // if (isLocal(hre)) {
  //   console.log(
  //     `Skipping installation for local network ${hre.network.name}...`
  //   );
  //   return true;
  // } else {
  if (
    !('MANAGEMENT_DAO_MULTISIG_LISTED_ONLY' in process.env) ||
    !('MANAGEMENT_DAO_MULTISIG_MIN_APPROVALS' in process.env) ||
    !('MANAGEMENT_DAO_MULTISIG_APPROVERS' in process.env)
  ) {
    console.log(`Needed env vars not set, skipping installation...`);
    return true;
  }

  console.log(
    `All env vars set, starting installation on network ${hre.network.name}...`
  );
  return false;
  // }
};
