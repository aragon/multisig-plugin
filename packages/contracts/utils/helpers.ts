import {
  PLUGIN_REPO_ENS_SUBDOMAIN_NAME,
  PLUGIN_REPO_PROXY_NAME,
} from '../plugin-settings';
import {
  SupportedNetworks,
  getLatestNetworkDeployment,
  getNetworkNameByAlias,
  getPluginEnsDomain,
  getNetworkByNameOrAlias,
} from '@aragon/osx-commons-configs';
import {UnsupportedNetworkError} from '@aragon/osx-commons-sdk';
import {Operation} from '@aragon/osx-commons-sdk';
import {
  DAO,
  DAO__factory,
  ENSSubdomainRegistrar__factory,
  ENS__factory,
  IAddrResolver__factory,
  PluginRepo,
  PluginRepoFactory,
  PluginRepo__factory,
  PluginRepoFactory__factory,
  PluginRepoRegistry__factory,
} from '@aragon/osx-ethers';
import {setBalance} from '@nomicfoundation/hardhat-network-helpers';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {BigNumber} from 'ethers';
import {Contract} from 'ethers';
import {LogDescription} from 'ethers/lib/utils';
import {ethers} from 'hardhat';
import {HardhatRuntimeEnvironment} from 'hardhat/types';

export function isLocal(hre: HardhatRuntimeEnvironment): boolean {
  return (
    hre.network.name === 'localhost' ||
    hre.network.name === 'hardhat' ||
    hre.network.name === 'coverage' ||
    hre.network.name === 'zkLocalTestnet'
  );
}

export function getProductionNetworkName(
  hre: HardhatRuntimeEnvironment
): string {
  let productionNetworkName: string;
  if (isLocal(hre)) {
    if (process.env.NETWORK_NAME) {
      productionNetworkName = process.env.NETWORK_NAME;
    } else {
      console.log(
        `No network has been provided in the '.env' file. Defaulting to '${SupportedNetworks.SEPOLIA}' as the production network.`
      );
      productionNetworkName = SupportedNetworks.SEPOLIA;
    }
  } else {
    productionNetworkName = hre.network.name;
  }

  if (getNetworkNameByAlias(productionNetworkName) === null) {
    throw new UnsupportedNetworkError(productionNetworkName);
  }

  return productionNetworkName;
}

export function pluginEnsDomain(hre: HardhatRuntimeEnvironment): string {
  const network = getNetworkNameByAlias(getProductionNetworkName(hre));
  if (network === null) {
    throw new UnsupportedNetworkError(getProductionNetworkName(hre));
  }

  const pluginEnsDomain = getPluginEnsDomain(network);
  return `${PLUGIN_REPO_ENS_SUBDOMAIN_NAME}.${pluginEnsDomain}`;
}

/**
 * try to get the plugin repo first
 * 1- env var PLUGIN_REPO_ADDRESS
 * 2- try to get the latest network deployment
 * 3- from the commons configs
 *    3.1- plugin repo factory address from env var
 *    3.2- plugin repo factory address from commons configs
 */
export async function findPluginRepo(
  hre: HardhatRuntimeEnvironment
): Promise<{pluginRepo: PluginRepo | null; ensDomain: string}> {
  const [deployer] = await hre.ethers.getSigners();
  const ensDomain = pluginEnsDomain(hre);

  // from env var
  if (process.env.PLUGIN_REPO_ADDRESS) {
    if (!isValidAddress(process.env.PLUGIN_REPO_ADDRESS)) {
      throw new Error(
        'Plugin Repo in .env is not a valid address (is not an address or is address zero)'
      );
    }

    return {
      pluginRepo: PluginRepo__factory.connect(
        process.env.PLUGIN_REPO_ADDRESS,
        deployer
      ),
      ensDomain,
    };
  }

  // from deployments
  const pluginRepo = await hre.deployments.getOrNull(PLUGIN_REPO_PROXY_NAME);
  if (pluginRepo) {
    console.log(
      'using the plugin repo from the deployments',
      pluginRepo.address
    );
    return {
      pluginRepo: PluginRepo__factory.connect(pluginRepo.address, deployer),
      ensDomain,
    };
  }

  // from commons configs
  let subdomainRegistrarAddress;
  const pluginRepoFactoryAddress = process.env.PLUGIN_REPO_FACTORY_ADDRESS;
  if (pluginRepoFactoryAddress) {
    if (!isValidAddress(pluginRepoFactoryAddress)) {
      throw new Error(
        'Plugin Repo Factory in .env is not valid address (is not an address or is address zero)'
      );
    }

    // get ENS registrar from the plugin factory provided
    const pluginRepoFactory = PluginRepoFactory__factory.connect(
      pluginRepoFactoryAddress,
      deployer
    );

    const pluginRepoRegistry = PluginRepoRegistry__factory.connect(
      await pluginRepoFactory.pluginRepoRegistry(),
      deployer
    );

    subdomainRegistrarAddress = await pluginRepoRegistry.subdomainRegistrar();
  } else {
    // get ENS registrar from the commons configs deployments
    const productionNetworkName: string = getProductionNetworkName(hre);
    const network = getNetworkNameByAlias(productionNetworkName);
    if (network === null) {
      throw new UnsupportedNetworkError(productionNetworkName);
    }
    const networkDeployments = getLatestNetworkDeployment(network);
    if (networkDeployments === null) {
      throw `Deployments are not available on network ${network}.`;
    }

    subdomainRegistrarAddress =
      networkDeployments.PluginENSSubdomainRegistrarProxy.address;
  }

  if (subdomainRegistrarAddress === ethers.constants.AddressZero) {
    // the network does not support ENS and the plugin repo could not be found by env var or deployments
    return {pluginRepo: null, ensDomain: ''};
  }

  const registrar = ENSSubdomainRegistrar__factory.connect(
    subdomainRegistrarAddress,
    deployer
  );

  // Check if the ens record exists already
  const ens = ENS__factory.connect(await registrar.ens(), deployer);
  const node = ethers.utils.namehash(ensDomain);
  const recordExists = await ens.recordExists(node);

  if (!recordExists) {
    return {pluginRepo: null, ensDomain};
  } else {
    const resolver = IAddrResolver__factory.connect(
      await ens.resolver(node),
      deployer
    );

    const pluginRepo = PluginRepo__factory.connect(
      await resolver.addr(node),
      deployer
    );
    return {
      pluginRepo,
      ensDomain,
    };
  }
}

export async function getManagementDao(
  hre: HardhatRuntimeEnvironment
): Promise<DAO> {
  const [deployer] = await hre.ethers.getSigners();

  const managementDaoAddress = process.env.MANAGEMENT_DAO_ADDRESS;

  // getting the management DAO from the env var
  if (!managementDaoAddress || !isValidAddress(managementDaoAddress)) {
    throw new Error(
      'Management DAO address in .env is not defined or is not a valid address (is not an address or is address zero)'
    );
  }

  return DAO__factory.connect(managementDaoAddress, deployer);
}

export async function getPluginRepoFactory(
  hre: HardhatRuntimeEnvironment
): Promise<PluginRepoFactory> {
  const [deployer] = await hre.ethers.getSigners();

  const pluginRepoFactoryAddress = process.env.PLUGIN_REPO_FACTORY_ADDRESS;

  // from env var
  if (!pluginRepoFactoryAddress || !isValidAddress(pluginRepoFactoryAddress)) {
    throw new Error(
      'Plugin Repo Factory address in .env is not defined or is not a valid address (is not an address or is address zero)'
    );
  }

  return PluginRepoFactory__factory.connect(pluginRepoFactoryAddress, deployer);
}

export async function impersonatedManagementDaoSigner(
  hre: HardhatRuntimeEnvironment
): Promise<SignerWithAddress> {
  return await (async () => {
    const managementDaoProxy = getManagementDao(hre);
    const signer = await hre.ethers.getImpersonatedSigner(
      (
        await managementDaoProxy
      ).address
    );
    await setBalance(signer.address, BigNumber.from(10).pow(18));
    return signer;
  })();
}

export type EventWithBlockNumber = {
  event: LogDescription;
  blockNumber: number;
};

export async function getPastVersionCreatedEvents(
  pluginRepo: PluginRepo
): Promise<EventWithBlockNumber[]> {
  const eventFilter = pluginRepo.filters['VersionCreated']();

  const logs = await pluginRepo.provider.getLogs({
    fromBlock: 0,
    toBlock: 'latest',
    address: pluginRepo.address,
    topics: eventFilter.topics,
  });

  return logs.map((log, index) => {
    return {
      event: pluginRepo.interface.parseLog(log),
      blockNumber: logs[index].blockNumber,
    };
  });
}

export type LatestVersion = {
  versionTag: PluginRepo.VersionStruct;
  pluginSetupContract: string;
  releaseMetadata: string;
  buildMetadata: string;
};

async function createVersion(
  pluginRepo: PluginRepo,
  release: number,
  setup: string,
  releaseMetadataURI: string,
  buildMetadataURI: string,
  signer: SignerWithAddress
) {
  const tx = await pluginRepo
    .connect(signer)
    .createVersion(
      release,
      setup,
      ethers.utils.hexlify(ethers.utils.toUtf8Bytes(buildMetadataURI)),
      ethers.utils.hexlify(ethers.utils.toUtf8Bytes(releaseMetadataURI))
    );

  await tx.wait();
}

export async function publishPlaceholderVersion(
  placeholderSetup: string,
  versionBuild: number,
  versionRelease: number,
  pluginRepo: PluginRepo,
  signer: any
) {
  for (let i = 0; i < versionBuild - 1; i++) {
    console.log('Publishing placeholder', i + 1);
    await createVersion(
      pluginRepo,
      versionRelease,
      placeholderSetup,
      `{}`,
      'placeholder-setup-build',
      signer
    );
  }
}

export function generateRandomName(length: number): string {
  const allowedCharacters = 'abcdefghijklmnopqrstuvwxyz-0123456789';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += allowedCharacters.charAt(
      Math.floor(Math.random() * allowedCharacters.length)
    );
  }
  return result;
}

export function isValidAddress(address: string): boolean {
  // check if the address is valid and not zero address
  return (
    ethers.utils.isAddress(address) && address !== ethers.constants.AddressZero
  );
}

export async function frameworkSupportsENS(
  pluginRepoFactory: PluginRepoFactory
): Promise<boolean> {
  const [deployer] = await ethers.getSigners();
  const pluginRepoRegistry = PluginRepoRegistry__factory.connect(
    await pluginRepoFactory.pluginRepoRegistry(),
    deployer
  );
  const subdomainRegistrar = await pluginRepoRegistry.subdomainRegistrar();

  return subdomainRegistrar !== ethers.constants.AddressZero;
}

export type Permission = {
  operation: Operation;
  where: {name: string; address: string};
  who: {name: string; address: string};
  permission: string;
  condition?: string;
  data?: string;
};

export async function isPermissionSetCorrectly(
  permissionManagerContract: Contract,
  {operation, where, who, permission, data = '0x'}: Permission
): Promise<boolean> {
  const permissionId = ethers.utils.id(permission);
  const isGranted = await permissionManagerContract.isGranted(
    where.address,
    who.address,
    permissionId,
    data
  );
  if (!isGranted && operation === Operation.Grant) {
    return false;
  }

  if (isGranted && operation === Operation.Revoke) {
    return false;
  }
  return true;
}

export const AragonOSxAsciiArt =
  "                                          ____   _____      \n     /\\                                  / __ \\ / ____|     \n    /  \\   _ __ __ _  __ _  ___  _ __   | |  | | (_____  __ \n   / /\\ \\ | '__/ _` |/ _` |/ _ \\| '_ \\  | |  | |\\___ \\ \\/ / \n  / ____ \\| | | (_| | (_| | (_) | | | | | |__| |____) >  <  \n /_/    \\_\\_|  \\__,_|\\__, |\\___/|_| |_|  \\____/|_____/_/\\_\\ \n                      __/ |                                 \n                     |___/                                  \n";
