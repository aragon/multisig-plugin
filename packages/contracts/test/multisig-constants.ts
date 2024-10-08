import {ethers} from 'hardhat';

export const MULTISIG_EVENTS = {
  MultisigSettingsUpdated: 'MultisigSettingsUpdated',
  Approved: 'Approved',
};

export const MULTISIG_INTERFACE = new ethers.utils.Interface([
  'function updateMultisigSettings(tuple(bool,uint16))',
  'function createProposal(bytes,tuple(address,uint256,bytes)[],uint256,bool,bool,uint64,uint64)',
  'function getProposal(uint256)',
]);

export const UPDATE_MULTISIG_SETTINGS_PERMISSION_ID = ethers.utils.id(
  'UPDATE_MULTISIG_SETTINGS_PERMISSION'
);

export const UPGRADE_PLUGIN_PERMISSION_ID = ethers.utils.id(
  'UPGRADE_PLUGIN_PERMISSION'
);

export const CREATE_PROPOSAL_PERMISSION_ID = ethers.utils.id(
  'CREATE_PROPOSAL_PERMISSION'
);

export const SET_TARGET_CONFIG_PERMISSION_ID = ethers.utils.id(
  'SET_TARGET_CONFIG_PERMISSION'
);

export const UPDATE_METADATA_PERMISSION_ID = ethers.utils.id(
  'UPDATE_METADATA_PERMISSION'
);

export const CREATE_PROPOSAL_SIGNATURE =
  'createProposal(bytes,(address,uint256,bytes)[],uint256,bool,bool,uint64,uint64)';

export const CREATE_PROPOSAL_SIGNATURE_IProposal =
  'createProposal(bytes,(address,uint256,bytes)[],uint64,uint64,bytes)';

export const ANY_ADDR = '0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF';

export enum Operation {
  call,
  delegatecall,
}

export type TargetConfig = {
  target: string;
  operation: number;
};

export const latestInitializerVersion = 2;
