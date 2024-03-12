import {MultisigApprover} from '../../generated/schema';
import { generateMemberEntityId, generateVoterEntityId } from '../../src/plugin/id';
import {
  handleMembersAdded,
  handleApproved,
  handleProposalExecuted,
  handleMembersRemoved,
  handleProposalCreated,
  handleMultisigSettingsUpdated,
} from '../../src/plugin/plugin';
import {
  ADDRESS_ONE,
  ADDRESS_TWO,
  ADDRESS_THREE,
  CONTRACT_ADDRESS,
  DAO_ADDRESS,
} from '../utils/constants';
import {
  createNewMembersAddedEvent,
  createNewApprovedEvent,
  createNewProposalExecutedEvent,
  createNewMembersRemovedEvent,
  createNewProposalCreatedEvent,
  getProposalCountCall,
  createMultisigProposalEntityState,
  createGetProposalCall,
  createNewMultisigSettingsUpdatedEvent,
  createMultisigPluginState,
  PLUGIN_PROPOSAL_ID,
  SNAPSHOT_BLOCK,
  ONE,
  TWO,
  START_DATE,
  END_DATE,
  ALLOW_FAILURE_MAP,
} from '../utils/events';
import {
  generatePluginEntityId,
  generateProposalEntityId,
  createDummyAction,
} from '@aragon/osx-commons-subgraph';
import {Address, BigInt, DataSourceContext} from '@graphprotocol/graph-ts';
import {
  afterEach,
  assert,
  beforeEach,
  clearStore,
  dataSourceMock,
  describe,
  test,
} from 'matchstick-as/assembly/index';

let actions = [createDummyAction(ADDRESS_THREE, '0', '0x00000000')];

const pluginAddress = Address.fromString(CONTRACT_ADDRESS);
const pluginEntityId = generatePluginEntityId(pluginAddress);
const pluginProposalId = BigInt.fromString(PLUGIN_PROPOSAL_ID);
const proposalEntityId = generateProposalEntityId(
  pluginAddress,
  pluginProposalId
);

export const METADATA = 'Some String Data ...';

describe('Plugin', () => {
  beforeEach(function () {
    let context = new DataSourceContext();
    context.setString('daoAddress', DAO_ADDRESS);
    dataSourceMock.setContext(context);
  });

  afterEach(() => {
    clearStore();
  });

  describe('ProposalCreated', () => {
    test('processes the event', () => {
      // create state
      createMultisigPluginState();

      // create calls
      getProposalCountCall(CONTRACT_ADDRESS, '1');
      createGetProposalCall(
        CONTRACT_ADDRESS,
        PLUGIN_PROPOSAL_ID,
        false,

        // ProposalParameters
        START_DATE,
        END_DATE,
        ONE,
        SNAPSHOT_BLOCK,

        // approvals
        ONE,

        actions,

        ALLOW_FAILURE_MAP
      );

      // create event
      let event = createNewProposalCreatedEvent(
        PLUGIN_PROPOSAL_ID,
        ADDRESS_ONE,
        START_DATE,
        END_DATE,
        METADATA,
        actions,
        ALLOW_FAILURE_MAP,
        CONTRACT_ADDRESS
      );

      // handle event
      handleProposalCreated(event);

      // checks
      assert.fieldEquals(
        'MultisigProposal',
        proposalEntityId,
        'id',
        proposalEntityId
      );
      assert.fieldEquals(
        'MultisigProposal',
        proposalEntityId,
        'dao',
        DAO_ADDRESS
      );
      assert.fieldEquals(
        'MultisigProposal',
        proposalEntityId,
        'plugin',
        pluginEntityId
      );
      assert.fieldEquals(
        'MultisigProposal',
        proposalEntityId,
        'pluginProposalId',
        PLUGIN_PROPOSAL_ID
      );
      assert.fieldEquals(
        'MultisigProposal',
        proposalEntityId,
        'creator',
        ADDRESS_ONE
      );
      assert.fieldEquals(
        'MultisigProposal',
        proposalEntityId,
        'startDate',
        START_DATE
      );
      assert.fieldEquals(
        'MultisigProposal',
        proposalEntityId,
        'endDate',
        END_DATE
      );
      assert.fieldEquals(
        'MultisigProposal',
        proposalEntityId,
        'metadata',
        METADATA
      );
      assert.fieldEquals(
        'MultisigProposal',
        proposalEntityId,
        'createdAt',
        event.block.timestamp.toString()
      );
      assert.fieldEquals(
        'MultisigProposal',
        proposalEntityId,
        'creationBlockNumber',
        event.block.number.toString()
      );
      assert.fieldEquals(
        'MultisigProposal',
        proposalEntityId,
        'snapshotBlock',
        SNAPSHOT_BLOCK
      );
      assert.fieldEquals(
        'MultisigProposal',
        proposalEntityId,
        'minApprovals',
        ONE
      );
      assert.fieldEquals(
        'MultisigProposal',
        proposalEntityId,
        'approvals',
        ONE
      );
      assert.fieldEquals(
        'MultisigProposal',
        proposalEntityId,
        'executed',
        'false'
      );
      assert.fieldEquals(
        'MultisigProposal',
        proposalEntityId,
        'allowFailureMap',
        ALLOW_FAILURE_MAP
      );

      // check MultisigPlugin
      assert.fieldEquals(
        'DaoPlugin',
        Address.fromString(CONTRACT_ADDRESS).toHexString(),
        'proposalCount',
        '1'
      );
    });
  });

  describe('Approved', () => {
    test('processes the event', () => {
      // create state
      let proposal = createMultisigProposalEntityState(
        proposalEntityId,
        DAO_ADDRESS,
        CONTRACT_ADDRESS,
        ADDRESS_ONE
      );

      // create calls
      createGetProposalCall(
        CONTRACT_ADDRESS,
        PLUGIN_PROPOSAL_ID,
        false,

        // ProposalParameters
        START_DATE,
        END_DATE,
        TWO, // minApprovals
        SNAPSHOT_BLOCK,

        // approvals
        ONE,

        actions,
        ALLOW_FAILURE_MAP
      );

      // create event
      let event = createNewApprovedEvent(
        PLUGIN_PROPOSAL_ID,
        ADDRESS_ONE,
        CONTRACT_ADDRESS
      );

      handleApproved(event);

      // checks
      const memberAddress = Address.fromString(ADDRESS_ONE);

      const memberEntityId = generateMemberEntityId(
        pluginAddress,
        memberAddress
      );

      const voterEntityId = generateVoterEntityId(memberEntityId, proposal.id);
      // check proposalVoter
      assert.fieldEquals(
        'MultisigProposalApprover',
        voterEntityId,
        'id',
        voterEntityId
      );
      assert.fieldEquals(
        'MultisigProposalApprover',
        voterEntityId,
        'approver',
        memberEntityId
      );
      assert.fieldEquals(
        'MultisigProposalApprover',
        voterEntityId,
        'proposal',
        proposal.id
      );
      assert.fieldEquals(
        'MultisigProposalApprover',
        voterEntityId,
        'createdAt',
        event.block.timestamp.toString()
      );

      // check proposal
      assert.fieldEquals('MultisigProposal', proposal.id, 'approvals', ONE);
      assert.fieldEquals(
        'MultisigProposal',
        proposal.id,
        'approvalReached',
        'false'
      );

      // create 2nd approve, to test approvals
      // create calls
      createGetProposalCall(
        CONTRACT_ADDRESS,
        PLUGIN_PROPOSAL_ID,
        false,

        // ProposalParameters
        START_DATE,
        END_DATE,
        TWO, // minApprovals
        SNAPSHOT_BLOCK,

        // approvals
        TWO,

        actions,
        ALLOW_FAILURE_MAP
      );

      // create event
      let event2 = createNewApprovedEvent(
        PLUGIN_PROPOSAL_ID,
        ADDRESS_TWO,
        CONTRACT_ADDRESS
      );

      handleApproved(event2);

      // Check
      assert.fieldEquals('MultisigProposal', proposal.id, 'approvals', TWO);
      assert.fieldEquals(
        'MultisigProposal',
        proposal.id,
        'approvalReached',
        'true'
      );
    });
  });

  describe('ProposalExecuted', () => {
    test('processes the event', () => {
      // create state
      createMultisigProposalEntityState(
        proposalEntityId,
        DAO_ADDRESS,
        CONTRACT_ADDRESS,
        ADDRESS_ONE
      );

      // create event
      let event = createNewProposalExecutedEvent('0', CONTRACT_ADDRESS);

      // handle event
      handleProposalExecuted(event);

      // checks
      assert.fieldEquals(
        'MultisigProposal',
        proposalEntityId,
        'id',
        proposalEntityId
      );
      assert.fieldEquals(
        'MultisigProposal',
        proposalEntityId,
        'executed',
        'true'
      );
      assert.fieldEquals(
        'MultisigProposal',
        proposalEntityId,
        'executionDate',
        event.block.timestamp.toString()
      );
      assert.fieldEquals(
        'MultisigProposal',
        proposalEntityId,
        'executionBlockNumber',
        event.block.number.toString()
      );
      assert.fieldEquals(
        'MultisigProposal',
        proposalEntityId,
        'executionTxHash',
        event.transaction.hash.toHexString()
      );
    });
  });

  describe('MembersAdded', () => {
    test('processes the event', () => {
      let userArray = [
        Address.fromString(ADDRESS_ONE),
        Address.fromString(ADDRESS_TWO),
      ];

      // create event
      let event = createNewMembersAddedEvent(userArray, CONTRACT_ADDRESS);

      // handle event
      handleMembersAdded(event);

      // checks
      let memberId =
        Address.fromString(CONTRACT_ADDRESS).toHexString() +
        '_' +
        userArray[0].toHexString();

      assert.fieldEquals('MultisigApprover', memberId, 'id', memberId);
      assert.fieldEquals(
        'MultisigApprover',
        memberId,
        'address',
        userArray[0].toHexString()
      );
      assert.fieldEquals(
        'MultisigApprover',
        memberId,
        'plugin',
        Address.fromString(CONTRACT_ADDRESS).toHexString()
      );
    });
  });

  describe('MembersRemoved', () => {
    test('processes the event', () => {
      // create state
      let memberAddresses = [
        Address.fromString(ADDRESS_ONE),
        Address.fromString(ADDRESS_TWO),
      ];

      for (let index = 0; index < memberAddresses.length; index++) {
        const user = memberAddresses[index].toHexString();
        const pluginId = Address.fromString(CONTRACT_ADDRESS).toHexString();
        let memberId = pluginId + '_' + user;
        let userEntity = new MultisigApprover(memberId);
        userEntity.plugin = Address.fromString(CONTRACT_ADDRESS).toHexString();
        userEntity.save();
      }

      // checks
      let memberId1 =
        Address.fromString(CONTRACT_ADDRESS).toHexString() +
        '_' +
        memberAddresses[0].toHexString();
      let memberId2 =
        Address.fromString(CONTRACT_ADDRESS).toHexString() +
        '_' +
        memberAddresses[1].toHexString();

      assert.fieldEquals('MultisigApprover', memberId1, 'id', memberId1);
      assert.fieldEquals('MultisigApprover', memberId2, 'id', memberId2);

      // create event
      let event = createNewMembersRemovedEvent(
        [memberAddresses[1]],
        CONTRACT_ADDRESS
      );

      // handle event
      handleMembersRemoved(event);

      // checks
      assert.fieldEquals('MultisigApprover', memberId1, 'id', memberId1);
      assert.notInStore('MultisigApprover', memberId2);
    });
  });

  describe('MultisigSettingsUpdated', () => {
    test('processes the event', () => {
      // create state
      let entityID = createMultisigPluginState().id;

      // create event
      let onlyListed = true;
      let minApproval = '5';

      let event = createNewMultisigSettingsUpdatedEvent(
        onlyListed,
        minApproval,
        CONTRACT_ADDRESS
      );

      // handle event
      handleMultisigSettingsUpdated(event);

      // checks
      assert.fieldEquals('DaoPlugin', entityID, 'onlyListed', `${onlyListed}`);
      assert.fieldEquals('DaoPlugin', entityID, 'minApprovals', minApproval);

      // create event
      onlyListed = false;
      minApproval = '4';

      event = createNewMultisigSettingsUpdatedEvent(
        onlyListed,
        minApproval,
        CONTRACT_ADDRESS
      );

      // handle event
      handleMultisigSettingsUpdated(event);

      // checks
      assert.fieldEquals('DaoPlugin', entityID, 'onlyListed', `${onlyListed}`);
      assert.fieldEquals('DaoPlugin', entityID, 'minApprovals', minApproval);
    });
  });
});
