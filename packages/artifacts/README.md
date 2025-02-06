# Multisig Plugin artifacts

This package contains the ABI of the Multisig Plugin for OSx, as well as the address of its plugin repository on each network. Install it with:

```sh
yarn add @aragon/multisig-plugin-artifacts
```

## Usage

```typescript
import {
    MultisigABI,
    IMultisigABI,
    ListedCheckConditionABI,
    MultisigSetupABI
} from "@aragon/multisig-plugin-artifacts";

import { addresses } from "@aragon/multisig-plugin-artifacts";
```

## Package generation

Install the dependencies:
```sh
yarn install
```

###  Prepare the ABI definition

```sh
yarn prepare-abi
```

The script will:
1. Move to `packages/contracts`.
2. Install its dependencies.
3. Compile the contracts using Hardhat.
4. Generate their ABI using Wagmi.
5. Save them on `src/abi.ts`.

### Publish to NPM

Ensure the package `version` is updated in `package.json` before publishing.

Check that only the intended files will be published:
```sh
yarn publish --dry-run
```

To publish the package to NPM, run:
```sh
yarn publish --access public
```
