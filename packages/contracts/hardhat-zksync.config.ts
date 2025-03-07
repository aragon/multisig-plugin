import './types/hardhat';
import {isZkSync, RichAccounts} from './utils/zksync-helpers';
import {addRpcUrlToNetwork} from '@aragon/osx-commons-configs';
import '@matterlabs/hardhat-zksync-deploy';
import '@matterlabs/hardhat-zksync-ethers';
import '@matterlabs/hardhat-zksync-node';
import '@matterlabs/hardhat-zksync-solc';
import '@matterlabs/hardhat-zksync-upgradable';
import '@matterlabs/hardhat-zksync-verify';
import '@nomicfoundation/hardhat-chai-matchers';
import '@nomicfoundation/hardhat-network-helpers';
import {config as dotenvConfig} from 'dotenv';
import fs from 'fs';
import 'hardhat-deploy';
import {extendEnvironment, HardhatUserConfig, task} from 'hardhat/config';
import {resolve} from 'path';
import 'solidity-coverage';

const dotenvConfigPath: string = process.env.DOTENV_CONFIG_PATH || '../../.env';
dotenvConfig({path: resolve(__dirname, dotenvConfigPath), override: true});

// Fetch the accounts specified in the .env file
function specifiedAccounts(): string[] {
  return process.env.PRIVATE_KEY ? process.env.PRIVATE_KEY.split(',') : [];
}

// check alchemy Api key existence

if (process.env.ALCHEMY_API_KEY) {
  addRpcUrlToNetwork(process.env.ALCHEMY_API_KEY);
} else {
  throw new Error('ALCHEMY_API_KEY in .env not set');
}

// Extend HardhatRuntimeEnvironment
extendEnvironment(hre => {
  hre.aragonToVerifyContracts = [];
});

task('compile').setAction(async (args, hre, runSuper) => {
  await runSuper(args);
  if (isZkSync(hre.network.name)) {
    // Copy zkSync specific build artifacts and cache to the default directories.
    // This ensures that we don't need to change import paths for artifacts in the project.
    fs.cpSync('./build/artifacts-zk', './artifacts', {
      recursive: true,
      force: true,
    });
    fs.cpSync('./build/cache-zk', './cache', {recursive: true, force: true});

    return;
  }

  fs.cpSync('./build/artifacts', './artifacts', {recursive: true, force: true});
  fs.cpSync('./build/cache', './cache', {recursive: true, force: true});
});

task('deploy-contracts')
  .addOptionalParam('tags', 'Specify which tags to deploy')
  .setAction(async (args, hre) => {
    await hre.run('compile');
    await hre.run('deploy', {
      tags: args.tags,
    });
  });

task('test').setAction(async (args, hre, runSuper) => {
  await hre.run('compile');
  const imp = await import('./test/test-utils/wrapper');

  const wrapper = await imp.Wrapper.create(
    hre.network.name,
    hre.ethers.provider
  );
  hre.wrapper = wrapper;

  await runSuper(args);
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more
const config: HardhatUserConfig = {
  zksolc: {
    compilerSource: 'binary',
    version: '1.5.0',
  },
  solidity: {
    version: '0.8.17',
    settings: {
      optimizer: {
        enabled: true,
        runs: 2000,
      },
      outputSelection: {
        '*': {
          '*': ['storageLayout'],
        },
      },
    },
  },
  defaultNetwork: 'zkLocalTestnet',
  networks: {
    zkLocalTestnet: {
      url: 'http://127.0.0.1:8011',
      ethNetwork: 'http://127.0.0.1:8545',
      zksync: true,
      deploy: ['./deploy'],
      gas: 15000000,
      blockGasLimit: 30000000,
      accounts: RichAccounts,
    },
    zksyncSepolia: {
      url: 'https://sepolia.era.zksync.dev',
      ethNetwork: 'sepolia',
      zksync: true,
      verifyURL:
        'https://explorer.sepolia.era.zksync.dev/contract_verification',
      deploy: ['./deploy'],
      accounts: specifiedAccounts(),
      forceDeploy: true,
    },
    zksyncMainnet: {
      url: 'https://mainnet.era.zksync.io',
      ethNetwork: 'mainnet',
      zksync: true,
      verifyURL:
        'https://zksync2-mainnet-explorer.zksync.io/contract_verification',
      deploy: ['./deploy'],
      accounts: specifiedAccounts(),
      forceDeploy: true,
    },
  },
  namedAccounts: {
    deployer: 0,
  },
  paths: {
    sources: './src',
    tests: './test',
    cache: './build/cache',
    artifacts: './build/artifacts',
    deploy: './deploy',
  },
  mocha: {
    timeout: 90_000, // 90 seconds // increase the timeout for subdomain validation tests
  },
};

export default config;
