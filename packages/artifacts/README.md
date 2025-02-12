# Multisig Plugin artifacts

This package contains the ABI of the Multisig Plugin for OSx, as well as the address of its plugin repository on each network. Install it with:

```sh
yarn add @aragon/multisig-plugin-artifacts
```

## Usage

```typescript
// ABI definitions
import {
    MultisigABI,
    IMultisigABI,
    ListedCheckConditionABI,
    MultisigSetupABI
} from "@aragon/multisig-plugin-artifacts";

// Plugin Repository addresses per-network
import { addresses } from "@aragon/multisig-plugin-artifacts";
```

You can also open [addresses.json](./src/addresses.json) directly.

## Development

### Building the package

Install the dependencies and generate the local ABI definitions.

```sh
yarn --ignore-scripts
yarn build
```

The `build` script will:
1. Move to `packages/contracts`.
2. Install its dependencies.
3. Compile the contracts using Hardhat.
4. Generate their ABI.
5. Extract their ABI and embed it into on `src/abi.ts`.

## Documentation

You can find all documentation regarding how to use this plugin in [Aragon's documentation here](https://docs.aragon.org/multisig/1.x/index.html).

## Contributing

If you like what we're doing and would love to support, please review our `CONTRIBUTING_GUIDE.md` [here](https://github.com/aragon/multisig-plugin/blob/main/CONTRIBUTIONS.md). We'd love to build with you.

## Security

If you believe you've found a security issue, we encourage you to notify us. We welcome working with you to resolve the issue promptly.

Security Contact Email: sirt@aragon.org

Please do not use the issue tracker for security issues.
