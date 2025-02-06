import {defineConfig} from '@wagmi/cli';
import {hardhat} from '@wagmi/cli/plugins';

export default defineConfig({
  // using abi instead of generated to avoid being ignored by git
  out: 'artifacts/abi.ts',
  plugins: [
    hardhat({
      project: './',
      artifacts: 'artifacts/src',
      exclude: ['**/test/**', '**/mocks/**'],
    }),
  ],
});
