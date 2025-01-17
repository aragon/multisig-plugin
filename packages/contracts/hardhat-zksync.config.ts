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

const ETH_KEY = process.env.ETH_KEY;
const accounts = ETH_KEY ? ETH_KEY.split(',') : [];

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

task('build-contracts').setAction(async (args, hre) => {
  await hre.run('compile');
  // TODO:Claudia (Is there a way without copying/pasting manually ? `paths` object below in the config
  // ! check if we want to only store on those folders or in both
  // !(check compile task params if one of them is the output folder)
  // creates `build` folder correctly, but it always appends `zk` in the end.
  const network = hre.network.name;
  if (isZkSync(network)) {
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
    await hre.run('build-contracts');
    await hre.run('deploy', {
      tags: args.tags,
    });
  });

task('test-contracts').setAction(async (args, hre) => {
  await hre.run('build-contracts');
  const imp = await import('./test/test-utils/wrapper');

  const wrapper = await imp.Wrapper.create(
    hre.network.name,
    hre.ethers.provider
  );
  hre.wrapper = wrapper;

  await hre.run('test');
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
      deploy: ['./deploy/new'],
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
      accounts: accounts,
      forceDeploy: true,
    },
    zksyncMainnet: {
      url: 'https://mainnet.era.zksync.io',
      ethNetwork: 'mainnet',
      zksync: true,
      verifyURL:
        'https://zksync2-mainnet-explorer.zksync.io/contract_verification',
      deploy: ['./deploy'],
      accounts: accounts,
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
