import {DEPLOYMENT_JSON_PATH} from '../plugin-settings';
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

export type AddressInfo = {
  name: string;
  address: string;
  blockNumber: number | undefined | null;
  txHash: string | undefined | null;
};

export function saveToDeployedJson(
  addressesInfo: AddressInfo[],
  newDeployment: boolean = false
) {
  const fs = require('fs');
  const outputPath = DEPLOYMENT_JSON_PATH;

  // Read existing JSON file
  let existingData: {[key: string]: AddressInfo} = {};

  if (fs.existsSync(outputPath) && !newDeployment) {
    const fileContent = fs.readFileSync(outputPath, 'utf8');
    existingData = JSON.parse(fileContent);
  }

  for (const addressInfo of addressesInfo) {
    existingData[addressInfo.name] = {
      address: addressInfo.address,
      blockNumber: addressInfo.blockNumber,
      txHash: addressInfo.txHash,
    };
  }

  fs.writeFileSync(outputPath, JSON.stringify(existingData, null, 2));
  console.log(`Plugin repo addresses saved to ${outputPath}`);
}

// hh-deploy cannot process files without default exports
export default async () => {};
