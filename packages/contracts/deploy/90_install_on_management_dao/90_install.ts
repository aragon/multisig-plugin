import {VERSION, METADATA} from '../../plugin-settings';
import {
  getManagementDao,
  isValidAddress,
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
  const {ethers} = hre;

  const [deployer] = await hre.ethers.getSigners();

  const approvers = process.env.MANAGEMENT_DAO_MULTISIG_APPROVERS?.split(
    ','
  ) || [deployer.address];
  const minApprovals = parseInt(
    process.env.MANAGEMENT_DAO_MULTISIG_MIN_APPROVALS || '1'
  );

  const listedOnly =
    process.env.MANAGEMENT_DAO_MULTISIG_LISTED_ONLY === 'false' ? false : true;

  // Get `managementDAO` address.
  const managementDAO = await getManagementDao(hre);

  // Get `PluginSetupProcessor` from env vars or commons config deployment
  const pspAddress = process.env.PLUGIN_SETUP_PROCESSOR_ADDRESS;

  if (!pspAddress || !isValidAddress(pspAddress)) {
    throw new Error(
      'PluginSetupProcessor address in .env is not defined or is not a valid address (is not an address or is address zero)'
    );
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

  const data = ethers.utils.defaultAbiCoder.encode(params, [
    approvers,
    [listedOnly, minApprovals],
    [ethers.constants.AddressZero, 0], // [target, operation]
    '0x', // metadata
  ]);

  const prepareTx = await pspContract.prepareInstallation(
    managementDAO.address,
    {
      pluginSetupRef,
      data,
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
  const permissionsToGrant: DAOStructs.MultiTargetPermissionStruct[] = [
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

  const applyPermissionTx = await managementDAO.applyMultiTargetPermissions(
    permissionsToGrant
  );
  await applyPermissionTx.wait();

  // Apply multisig plugin to the managementDAO
  const applyTx = await pspContract.applyInstallation(managementDAO.address, {
    helpersHash: hashHelpers(
      installationPreparedEvent.preparedSetupData.helpers
    ),
    permissions: installationPreparedEvent.preparedSetupData.permissions,
    plugin: installationPreparedEvent.plugin,
    pluginSetupRef,
  });
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
  const permissionsToRevoke: DAOStructs.MultiTargetPermissionStruct[] = [
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
      permissionId: DAO_PERMISSIONS.ROOT_PERMISSION_ID,
    },
  ];

  const revokePermissionsTx = await managementDAO.applyMultiTargetPermissions(
    permissionsToRevoke
  );
  await revokePermissionsTx.wait();

  console.log('Permissions revoked....');

  // check if the permissions are revoked correctly
  for (const permission of permissionsToRevoke) {
    const hasPermission = await managementDAO.hasPermission(
      permission.where,
      permission.who,
      permission.permissionId,
      '0x'
    );
    if (hasPermission) {
      throw new Error(
        `Permission ${permission.permissionId} not revoked for ${permission.who} on ${permission.where}`
      );
    }
  }
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
func.skip = async () => {
  console.log(`\n✨ Install on Management DAO:`);

  if (
    !('MANAGEMENT_DAO_MULTISIG_LISTED_ONLY' in process.env) ||
    !('MANAGEMENT_DAO_MULTISIG_MIN_APPROVALS' in process.env) ||
    !('MANAGEMENT_DAO_MULTISIG_APPROVERS' in process.env)
  ) {
    console.log(`Needed env vars not set, skipping installation...`);
    return true;
  } else {
    return !areEnvVarsValid(
      process.env.MANAGEMENT_DAO_MULTISIG_LISTED_ONLY!,
      process.env.MANAGEMENT_DAO_MULTISIG_MIN_APPROVALS!,
      process.env.MANAGEMENT_DAO_MULTISIG_APPROVERS!.split(',')
    );
  }
};

function areEnvVarsValid(
  listedOnly: string,
  minApprovals: string,
  approvers: string[]
) {
  // Validate LISTED_ONLY is boolean
  if (listedOnly !== 'true' && listedOnly !== 'false') {
    console.log(
      `MANAGEMENT_DAO_MULTISIG_LISTED_ONLY must be 'true' or 'false'`
    );
    return false;
  }

  // Validate MIN_APPROVALS is a valid number

  if (isNaN(parseInt(minApprovals)) || parseInt(minApprovals) < 1) {
    console.log(
      `MANAGEMENT_DAO_MULTISIG_MIN_APPROVALS must be a positive number`
    );
    return false;
  }

  // Validate APPROVERS is a non-empty list
  if (!approvers || approvers.length === 0) {
    console.log(
      `MANAGEMENT_DAO_MULTISIG_APPROVERS must contain at least one valid address`
    );
    return false;
  } else {
    for (const approver of approvers) {
      if (!isValidAddress(approver)) {
        console.log(
          `${approver} in MANAGEMENT_DAO_MULTISIG_APPROVERS is not a valid address`
        );
        return false;
      }
    }
  }

  console.log('All env vars set properly');
  return true;
}
