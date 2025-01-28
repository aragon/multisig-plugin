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
