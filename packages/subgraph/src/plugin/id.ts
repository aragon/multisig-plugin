import {
  generateEntityIdFromAddress,
  generateEntityIdFromBigInt,
} from '@aragon/osx-commons-subgraph';
import {Address, BigInt} from '@graphprotocol/graph-ts';

export function generateMemberEntityId(
  pluginAddress: Address,
  memberAddress: Address
): string {
  return [
    generateEntityIdFromAddress(pluginAddress),
    generateEntityIdFromAddress(memberAddress),
  ].join('_');
}

export function generateVoterEntityId(
  memberEntityId: string,
  proposalId: BigInt
): string {
  return [memberEntityId, generateEntityIdFromBigInt(proposalId)].join('_');
}
