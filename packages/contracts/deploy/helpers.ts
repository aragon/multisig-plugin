import {DEPLOYMENT_JSON_PATH, PLUGIN_CONTRACT_NAME} from '../plugin-settings';
import {isLocal} from '../utils/helpers';
import {
  getLatestNetworkDeployment,
  getNetworkByNameOrAlias,
} from '@aragon/osx-commons-configs';
import {HardhatRuntimeEnvironment} from 'hardhat/types';

export function getLatestContractAddress(
  contractName: string,
  hre: HardhatRuntimeEnvironment
): string {
  const networkName = hre.network.name;

  const osxNetworkName = getNetworkByNameOrAlias(networkName);
  if (!osxNetworkName) {
    if (isLocal(hre)) {
      return '';
    }
    throw new Error(`Failed to find network ${networkName}`);
  }

  const latestNetworkDeployment = getLatestNetworkDeployment(
    osxNetworkName.name
  );
  if (latestNetworkDeployment && contractName in latestNetworkDeployment) {
    // safe cast due to conditional above, but we return the fallback string anyhow
    const key = contractName as keyof typeof latestNetworkDeployment;
    return latestNetworkDeployment[key]?.address ?? '';
  }
  return '';
}

export async function forkNetwork(
  hre: HardhatRuntimeEnvironment,
  fork_url: string
) {
  await hre.network.provider.request({
    method: 'hardhat_reset',
    params: [
      {
        forking: {
          jsonRpcUrl: fork_url,
        },
      },
    ],
  });
}

export function savePluginRepoAddress(
  hre: HardhatRuntimeEnvironment,
  pluginRepoAddress: string,
  pluginRepoImplementationAddress: string,
  txHash: string,
  blockNumber: number | undefined
) {
  // Write plugin repo address to file
  const fs = require('fs');
  const outputPath = DEPLOYMENT_JSON_PATH;

  const addressInformation = {
    [PLUGIN_CONTRACT_NAME + 'RepoProxy']: {
      address: pluginRepoAddress,
      blockNumber: blockNumber,
      deploymentTx: txHash,
    },
    [PLUGIN_CONTRACT_NAME + 'RepoImplementation']: {
      address: pluginRepoImplementationAddress,
      blockNumber: null,
      deploymentTx: null,
    },
  };

  fs.writeFileSync(outputPath, JSON.stringify(addressInformation, null, 2));
  console.log(`Plugin repo addresses saved to ${outputPath}`);
}

// hh-deploy cannot process files without default exports
export default async () => {};
