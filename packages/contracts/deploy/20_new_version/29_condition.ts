import {
  LISTED_CHECK_CONDITION_CONTRACT_NAME,
  PLUGIN_SETUP_CONTRACT_NAME,
} from '../../plugin-settings';
import {MultisigSetup__factory} from '../../typechain';
import {Multisig__factory} from '../../typechain/factories/src';
import {DeployFunction} from 'hardhat-deploy/types';
import {HardhatRuntimeEnvironment} from 'hardhat/types';
import path from 'path';

/**
 * Deploys the plugin setup contract with the plugin implementation inside.
 * @param {HardhatRuntimeEnvironment} hre
 */
const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  console.log(`\n🏗️  ${path.basename(__filename)}:`);
  console.log(
    `Deploy a dummy ${LISTED_CHECK_CONDITION_CONTRACT_NAME} contract, only for the purpose of verification on explorers`
  );

  const [deployer] = await hre.ethers.getSigners();
  const {deployments} = hre;
  const {deploy} = deployments;

  // Get the plugin setup address
  const setupDeployment = await deployments.get(PLUGIN_SETUP_CONTRACT_NAME);
  const setup = MultisigSetup__factory.connect(
    setupDeployment.address,
    deployer
  );
  // Get the plugin implementation address
  const implementationAddress = await setup.implementation()

  const res = await deploy(LISTED_CHECK_CONDITION_CONTRACT_NAME, {
    from: deployer.address,
    args: [implementationAddress],
    log: true,
  });

  hre.aragonToVerifyContracts.push({
    address: res.address,
    args: [implementationAddress],
  });

  console.log(
    `Deployed ${LISTED_CHECK_CONDITION_CONTRACT_NAME} contract at '${res.address}'`
  );
};

export default func;
func.tags = [LISTED_CHECK_CONDITION_CONTRACT_NAME, 'NewVersion'];
