import {createDaoProxy} from '../20_integration-testing/test-helpers';
import {
  Addresslist__factory,
  CustomExecutorMock__factory,
  ERC1967Proxy__factory,
  IERC165Upgradeable__factory,
  IMembership__factory,
  IMultisig__factory,
  IPlugin__factory,
  IProposal__factory,
  IProtocolVersion__factory,
  ListedCheckCondition__factory,
  ProxyFactory__factory,
} from '../../typechain';
import {ExecutedEvent} from '../../typechain/@aragon/osx-commons-contracts/src/dao/IDAO';
import {ProxyCreatedEvent} from '../../typechain/@aragon/osx-commons-contracts/src/utils/deployment/ProxyFactory';
import {
  ApprovedEvent,
  ProposalCreatedEvent,
  ProposalExecutedEvent,
} from '../../typechain/src/Multisig';
import {
  ANY_ADDR,
  CREATE_PROPOSAL_PERMISSION_ID,
  CREATE_PROPOSAL_SIGNATURE,
  CREATE_PROPOSAL_SIGNATURE_IProposal,
  EXECUTE_PROPOSAL_PERMISSION_ID,
  MULTISIG_EVENTS,
  MULTISIG_INTERFACE,
  Operation,
  SET_TARGET_CONFIG_PERMISSION_ID,
  TargetConfig,
  UPDATE_MULTISIG_SETTINGS_PERMISSION_ID,
  latestInitializerVersion,
} from '../multisig-constants';
import {Multisig__factory, Multisig} from '../test-utils/typechain-versions';
import {
  getInterfaceId,
  findEvent,
  findEventTopicLog,
  TIME,
  DAO_PERMISSIONS,
} from '@aragon/osx-commons-sdk';
import {
  DAO,
  DAOStructs,
  DAO__factory,
  PluginUUPSUpgradeableV1Mock__factory,
} from '@aragon/osx-ethers';
import {defaultAbiCoder} from '@ethersproject/abi';
import {loadFixture, time} from '@nomicfoundation/hardhat-network-helpers';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {expect} from 'chai';
import {BigNumber} from 'ethers';
import {keccak256} from 'ethers/lib/utils';
import {ethers} from 'hardhat';

type FixtureResult = {
  deployer: SignerWithAddress;
  alice: SignerWithAddress;
  bob: SignerWithAddress;
  carol: SignerWithAddress;
  dave: SignerWithAddress;
  eve: SignerWithAddress;
  initializedPlugin: Multisig;
  uninitializedPlugin: Multisig;
  defaultInitData: {
    members: string[];
    settings: Multisig.MultisigSettingsStruct;
    targetConfig: TargetConfig;
    metadata: string;
  };
  dao: DAO;
  dummyActions: DAOStructs.ActionStruct[];
  dummyMetadata: string;
};

let chainId: number;

async function createProposalId(
  pluginAddress: string,
  actions: DAOStructs.ActionStruct[],
  metadata: string
): Promise<BigNumber> {
  const blockNumber = (await ethers.provider.getBlock('latest')).number;
  const salt = keccak256(
    defaultAbiCoder.encode(
      ['tuple(address to,uint256 value,bytes data)[]', 'bytes'],
      [actions, metadata]
    )
  );
  return BigNumber.from(
    keccak256(
      defaultAbiCoder.encode(
        ['uint256', 'uint256', 'address', 'bytes32'],
        [chainId, blockNumber + 1, pluginAddress, salt]
      )
    )
  );
}

async function fixture(): Promise<FixtureResult> {
  const [deployer, alice, bob, carol, dave, eve] = await ethers.getSigners();

  // Deploy a DAO proxy.
  const dummyMetadata = '0x12345678';
  const dao = await createDaoProxy(deployer, dummyMetadata);

  // Deploy a plugin proxy factory containing the multisig implementation.
  const pluginImplementation = await new Multisig__factory(deployer).deploy();
  const proxyFactory = await new ProxyFactory__factory(deployer).deploy(
    pluginImplementation.address
  );

  // Deploy an initialized plugin proxy.
  const defaultInitData = {
    members: [alice.address, bob.address, carol.address],
    settings: {
      onlyListed: true,
      minApprovals: 2,
    },
    targetConfig: {
      target: dao.address,
      operation: Operation.call,
    },
    metadata: '0x11',
  };
  const pluginInitdata = pluginImplementation.interface.encodeFunctionData(
    'initialize',
    [
      dao.address,
      defaultInitData.members,
      defaultInitData.settings,
      defaultInitData.targetConfig,
      defaultInitData.metadata,
    ]
  );
  const deploymentTx1 = await proxyFactory.deployUUPSProxy(pluginInitdata);
  const proxyCreatedEvent1 = findEvent<ProxyCreatedEvent>(
    await deploymentTx1.wait(),
    proxyFactory.interface.getEvent('ProxyCreated').name
  );
  const initializedPlugin = Multisig__factory.connect(
    proxyCreatedEvent1.args.proxy,
    deployer
  );

  // Deploy an uninitialized plugin proxy.
  const deploymentTx2 = await proxyFactory.deployUUPSProxy([]);
  const proxyCreatedEvent2 = findEvent<ProxyCreatedEvent>(
    await deploymentTx2.wait(),
    proxyFactory.interface.getEvent('ProxyCreated').name
  );
  const uninitializedPlugin = Multisig__factory.connect(
    proxyCreatedEvent2.args.proxy,
    deployer
  );

  // Provide a dummy action array.
  const dummyActions: DAOStructs.ActionStruct[] = [
    {
      to: deployer.address,
      data: '0x1234',
      value: 0,
    },
  ];

  await dao.grant(
    initializedPlugin.address,
    ANY_ADDR,
    EXECUTE_PROPOSAL_PERMISSION_ID
  );

  await dao.grant(
    uninitializedPlugin.address,
    ANY_ADDR,
    EXECUTE_PROPOSAL_PERMISSION_ID
  );

  return {
    deployer,
    alice,
    bob,
    carol,
    dave,
    eve,
    initializedPlugin,
    uninitializedPlugin,
    defaultInitData,
    dao,
    dummyActions,
    dummyMetadata,
  };
}

async function loadFixtureAndGrantCreatePermission(): Promise<FixtureResult> {
  const data = await loadFixture(fixture);
  const {deployer, alice, dao, initializedPlugin, uninitializedPlugin} = data;

  const condition = await new ListedCheckCondition__factory(deployer).deploy(
    initializedPlugin.address
  );

  await dao.grantWithCondition(
    initializedPlugin.address,
    ANY_ADDR,
    CREATE_PROPOSAL_PERMISSION_ID,
    condition.address
  );

  await dao.grantWithCondition(
    uninitializedPlugin.address,
    ANY_ADDR,
    CREATE_PROPOSAL_PERMISSION_ID,
    condition.address
  );

  return data;
}

describe('Multisig', function () {
  before(async () => {
    chainId = (await ethers.provider.getNetwork()).chainId;
  });
  describe('initialize', async () => {
    it('reverts if trying to re-initialize', async () => {
      const {dao, initializedPlugin, defaultInitData} = await loadFixture(
        fixture
      );

      // Try to reinitialize the initialized plugin.
      await expect(
        initializedPlugin.initialize(
          dao.address,
          defaultInitData.members,
          defaultInitData.settings,
          defaultInitData.targetConfig,
          defaultInitData.metadata
        )
      ).to.be.revertedWithCustomError(initializedPlugin, 'AlreadyInitialized');
    });

    it('adds the initial addresses to the address list', async () => {
      const {
        dao,
        uninitializedPlugin: plugin,
        defaultInitData,
      } = await loadFixture(fixture);

      // Check that the uninitialized plugin has no members.
      expect(await plugin.addresslistLength()).to.equal(0);

      // Initialize the plugin.
      await plugin.initialize(
        dao.address,
        defaultInitData.members,
        defaultInitData.settings,
        defaultInitData.targetConfig,
        defaultInitData.metadata
      );

      // Check that all members from the init data have been listed as members.
      expect(await plugin.addresslistLength()).to.equal(
        defaultInitData.members.length
      );
      const promises = defaultInitData.members.map(member =>
        plugin.isListed(member)
      );
      (await Promise.all(promises)).forEach(isListedResult => {
        expect(isListedResult).to.be.true;
      });
    });

    it('sets the `minApprovals`', async () => {
      const {initializedPlugin, defaultInitData} = await loadFixture(fixture);
      expect(
        (await initializedPlugin.multisigSettings()).minApprovals
      ).to.be.eq(defaultInitData.settings.minApprovals);
    });

    it('sets the `metadata`', async () => {
      const {initializedPlugin, defaultInitData} = await loadFixture(fixture);
      expect(await initializedPlugin.getMetadata()).to.be.eq(
        defaultInitData.metadata
      );
    });

    it('sets `onlyListed`', async () => {
      const {initializedPlugin, defaultInitData} = await loadFixture(fixture);
      expect((await initializedPlugin.multisigSettings()).onlyListed).to.be.eq(
        defaultInitData.settings.onlyListed
      );
    });

    it('emits `MultisigSettingsUpdated` during initialization', async () => {
      const {uninitializedPlugin, defaultInitData, dao} = await loadFixture(
        fixture
      );
      await expect(
        uninitializedPlugin.initialize(
          dao.address,
          defaultInitData.members,
          defaultInitData.settings,
          defaultInitData.targetConfig,
          defaultInitData.metadata
        )
      )
        .to.emit(uninitializedPlugin, MULTISIG_EVENTS.MultisigSettingsUpdated)
        .withArgs(
          defaultInitData.settings.onlyListed,
          defaultInitData.settings.minApprovals
        );
    });

    it('reverts if the member list is longer than uint16 max', async () => {
      const {uninitializedPlugin, alice, defaultInitData, dao} =
        await loadFixture(fixture);

      // Create a member list causing an overflow during initialization.
      const uint16MaxValue = 2 ** 16 - 1; // = 65535
      const overflowingMemberList = new Array(uint16MaxValue + 1).fill(
        alice.address
      );

      // Try to initialize the plugin with a list of new members causing an overflow.
      await expect(
        uninitializedPlugin.initialize(
          dao.address,
          overflowingMemberList,
          defaultInitData.settings,
          defaultInitData.targetConfig,
          defaultInitData.metadata,
          {
            gasLimit: BigNumber.from(10).pow(8).toNumber(),
          }
        )
      )
        .to.revertedWithCustomError(
          uninitializedPlugin,
          'AddresslistLengthOutOfBounds'
        )
        .withArgs(uint16MaxValue, overflowingMemberList.length);
    });
  });

  describe('reinitialize', async () => {
    it('reverts if trying to re-reinitializeFrom', async () => {
      const {uninitializedPlugin, deployer} = await loadFixture(fixture);

      const encodedData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint8', 'bytes'],
        [deployer.address, Operation.delegatecall, '0x']
      );

      // reinitialize the plugin.
      await uninitializedPlugin.initializeFrom(
        latestInitializerVersion,
        encodedData
      );

      // Try to reinitialize the  plugin.
      await expect(
        uninitializedPlugin.initializeFrom(
          latestInitializerVersion,
          encodedData
        )
      ).to.be.revertedWith('Initializable: contract is already initialized');
    });

    it('reverts if trying to initializeFrom an initialized plugin', async () => {
      const {initializedPlugin, deployer} = await loadFixture(fixture);

      const encodedDummyTarget = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint8'],
        [deployer.address, Operation.delegatecall]
      );

      // Try to reinitialize the  plugin.
      await expect(
        initializedPlugin.initializeFrom(
          latestInitializerVersion,
          encodedDummyTarget
        )
      ).to.be.revertedWith('Initializable: contract is already initialized');
    });

    // todo add test for checking that plugins already initialized on a previous version can not be initialized again
    it('reverts if trying to initialize lower version plugin');

    it('sets the `_targetConfig` when initializing an uninitialized plugin', async () => {
      const {uninitializedPlugin, deployer} = await loadFixture(fixture);

      const encodedData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'uint8', 'bytes'],
        [deployer.address, Operation.delegatecall, '0x']
      );

      // reinitialize the plugin.
      await uninitializedPlugin.initializeFrom(
        latestInitializerVersion,
        encodedData
      );

      expect((await uninitializedPlugin.getTargetConfig()).target).to.be.eq(
        deployer.address
      );
      expect((await uninitializedPlugin.getTargetConfig()).operation).to.be.eq(
        Operation.delegatecall
      );
    });
  });

  describe('ERC-165', async () => {
    it('does not support the empty interface', async () => {
      const {initializedPlugin: plugin} = await loadFixture(fixture);
      expect(await plugin.supportsInterface('0xffffffff')).to.be.false;
    });

    it('supports the `IERC165Upgradeable` interface', async () => {
      const {initializedPlugin: plugin} = await loadFixture(fixture);
      const iface = IERC165Upgradeable__factory.createInterface();
      expect(await plugin.supportsInterface(getInterfaceId(iface))).to.be.true;
    });

    it('supports the `IPlugin` interface', async () => {
      const {initializedPlugin: plugin} = await loadFixture(fixture);
      const iface = IPlugin__factory.createInterface();
      expect(await plugin.supportsInterface(getInterfaceId(iface))).to.be.true;
    });

    it('supports the `IProtocolVersion` interface', async () => {
      const {initializedPlugin: plugin} = await loadFixture(fixture);
      const iface = IProtocolVersion__factory.createInterface();
      expect(await plugin.supportsInterface(getInterfaceId(iface))).to.be.true;
    });

    it('supports the `IProposal` interface', async () => {
      const {initializedPlugin: plugin} = await loadFixture(fixture);
      const iface = IProposal__factory.createInterface();
      expect(await plugin.supportsInterface(getInterfaceId(iface))).to.be.true;
    });

    it('supports the `IMembership` interface', async () => {
      const {initializedPlugin: plugin} = await loadFixture(fixture);
      const iface = IMembership__factory.createInterface();
      expect(await plugin.supportsInterface(getInterfaceId(iface))).to.be.true;
    });

    it('supports the `Addresslist` interface', async () => {
      const {initializedPlugin: plugin} = await loadFixture(fixture);
      const iface = Addresslist__factory.createInterface();
      expect(await plugin.supportsInterface(getInterfaceId(iface))).to.be.true;
    });

    it('supports the `IMultisig` interface', async () => {
      const {initializedPlugin: plugin} = await loadFixture(fixture);
      const iface = IMultisig__factory.createInterface();
      expect(await plugin.supportsInterface(getInterfaceId(iface))).to.be.true;
    });

    it('supports the `Multisig` interface', async () => {
      const {initializedPlugin: plugin} = await loadFixture(fixture);
      const interfaceId = getInterfaceId(MULTISIG_INTERFACE);
      expect(await plugin.supportsInterface(interfaceId)).to.be.true;
    });
  });

  describe('updateMultisigSettings', async () => {
    it('reverts if the caller misses the `UPDATE_MULTISIG_SETTINGS_PERMISSION` permission', async () => {
      const {
        alice,
        initializedPlugin: plugin,
        dao,
      } = await loadFixture(fixture);

      // Check that Alice hasn't `UPDATE_MULTISIG_SETTINGS_PERMISSION_ID` permission on the Multisig plugin.
      expect(
        await dao.hasPermission(
          plugin.address,
          alice.address,
          UPDATE_MULTISIG_SETTINGS_PERMISSION_ID,
          []
        )
      ).to.be.false;

      // Expect Alice's `updateMultisigSettings` call to be reverted because she hasn't `UPDATE_MULTISIG_SETTINGS_PERMISSION_ID`
      // permission on the Multisig plugin.
      const newSettings: Multisig.MultisigSettingsStruct = {
        onlyListed: false,
        minApprovals: 1,
      };
      await expect(plugin.connect(alice).updateMultisigSettings(newSettings))
        .to.be.revertedWithCustomError(plugin, 'DaoUnauthorized')
        .withArgs(
          dao.address,
          plugin.address,
          alice.address,
          UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
        );
    });

    it('reverts when setting `minApprovals` to a value greater than the address list length', async () => {
      const {
        alice,
        initializedPlugin: plugin,
        dao,
      } = await loadFixture(fixture);

      // Grant Alice the permission to update settings.
      await dao.grant(
        plugin.address,
        alice.address,
        UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
      );

      // Create settings where `minApprovals` is greater than the address list length
      const addresslistLength = (await plugin.addresslistLength()).toNumber();
      const badSettings: Multisig.MultisigSettingsStruct = {
        onlyListed: true,
        minApprovals: addresslistLength + 1,
      };

      // Try to update the multisig settings
      await expect(plugin.connect(alice).updateMultisigSettings(badSettings))
        .to.be.revertedWithCustomError(plugin, 'MinApprovalsOutOfBounds')
        .withArgs(addresslistLength, badSettings.minApprovals);
    });

    it('reverts when setting `minApprovals` to 0', async () => {
      const {
        alice,
        initializedPlugin: plugin,
        dao,
      } = await loadFixture(fixture);

      // Grant Alice the permission to update settings.
      await dao.grant(
        plugin.address,
        alice.address,
        UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
      );

      // Try as Alice to update the settings with `minApprovals` being 0.
      const badSettings: Multisig.MultisigSettingsStruct = {
        onlyListed: true,
        minApprovals: 0,
      };
      await expect(plugin.connect(alice).updateMultisigSettings(badSettings))
        .to.be.revertedWithCustomError(plugin, 'MinApprovalsOutOfBounds')
        .withArgs(1, 0);
    });

    it('emits `MultisigSettingsUpdated` when `updateMultisigSettings` gets called', async () => {
      const {
        alice,
        initializedPlugin: plugin,
        defaultInitData,
        dao,
      } = await loadFixture(fixture);

      // Grant Alice the permission to update settings.
      await dao.grant(
        plugin.address,
        alice.address,
        UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
      );

      // Update the settings as Alice.
      await expect(
        plugin.connect(alice).updateMultisigSettings(defaultInitData.settings)
      )
        .to.emit(plugin, MULTISIG_EVENTS.MultisigSettingsUpdated)
        .withArgs(
          defaultInitData.settings.onlyListed,
          defaultInitData.settings.minApprovals
        );
    });
  });

  describe('isListed', async () => {
    it('returns false, if a user is not listed', async () => {
      const {dave, initializedPlugin: plugin} = await loadFixture(fixture);
      expect(await plugin.isListed(dave.address)).to.equal(false);
    });

    it('returns true, if a user is listed', async () => {
      const {alice, initializedPlugin: plugin} = await loadFixture(fixture);
      expect(await plugin.isListed(alice.address)).to.equal(true);
    });
  });

  describe('isMember', async () => {
    it('returns false, if user is not a member', async () => {
      const {dave, initializedPlugin: plugin} = await loadFixture(fixture);
      expect(await plugin.isMember(dave.address)).to.be.false;
    });

    it('returns true if user a user is a member', async () => {
      const {alice, initializedPlugin: plugin} = await loadFixture(fixture);
      expect(await plugin.isMember(alice.address)).to.be.true;
    });
  });

  describe('addAddresses', async () => {
    it('reverts if the caller misses the `UPDATE_MULTISIG_SETTINGS_PERMISSION_ID` permission', async () => {
      const {
        alice,
        dave,
        eve,
        initializedPlugin: plugin,
        dao,
      } = await loadFixture(fixture);

      // Check that the Alice hasn't `UPDATE_MULTISIG_SETTINGS_PERMISSION_ID` permission on the Multisig plugin.
      expect(
        await dao.hasPermission(
          plugin.address,
          alice.address,
          UPDATE_MULTISIG_SETTINGS_PERMISSION_ID,
          []
        )
      ).to.be.false;

      // Expect Alice's `addAddresses` call to be reverted because she hasn't `UPDATE_MULTISIG_SETTINGS_PERMISSION_ID`
      // permission on the Multisig plugin.
      await expect(
        plugin.connect(alice).addAddresses([dave.address, eve.address])
      )
        .to.be.revertedWithCustomError(plugin, 'DaoUnauthorized')
        .withArgs(
          dao.address,
          plugin.address,
          alice.address,
          UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
        );
    });

    it('reverts if the member list would become longer than uint16 max', async () => {
      const {
        initializedPlugin: plugin,
        alice,
        dave,
        dao,
      } = await loadFixture(fixture);

      // Grant Alice the permission to update settings.
      await dao.grant(
        plugin.address,
        alice.address,
        UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
      );

      const currentMemberCount = (
        await plugin.callStatic.addresslistLength()
      ).toNumber();

      // Create list of new members causing an overflow.
      const uint16MaxValue = 2 ** 16 - 1; // = 65535
      const overflowingNewMemberList = new Array(
        uint16MaxValue - currentMemberCount + 1
      ).fill(dave.address);

      // Try to add a list of new members causing an overflow as Alice.
      await expect(plugin.connect(alice).addAddresses(overflowingNewMemberList))
        .to.revertedWithCustomError(plugin, 'AddresslistLengthOutOfBounds')
        .withArgs(uint16MaxValue, uint16MaxValue + 1);
    });

    it('adds new members to the address list and emit the `MembersAdded` event', async () => {
      const {
        alice,
        dave,
        eve,
        initializedPlugin: plugin,
        dao,
      } = await loadFixture(fixture);

      // Grant Alice the permission to update settings.
      await dao.grant(
        plugin.address,
        alice.address,
        UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
      );

      // Check that Dave and Eve are not listed yet.
      expect(await plugin.isListed(dave.address)).to.equal(false);
      expect(await plugin.isListed(eve.address)).to.equal(false);

      // Call `addAddresses` as Alice to add Dave and Eve.
      await expect(
        plugin.connect(alice).addAddresses([dave.address, eve.address])
      )
        .to.emit(plugin, 'MembersAdded')
        .withArgs([dave.address, eve.address]);

      // Check that Dave and Eve are listed now.
      expect(await plugin.isListed(dave.address)).to.equal(true);
      expect(await plugin.isListed(eve.address)).to.equal(true);
    });
  });

  describe('removeAddresses', async () => {
    it('reverts if the caller misses the `UPDATE_MULTISIG_SETTINGS_PERMISSION_ID` permission', async () => {
      const {
        alice,
        bob,
        carol,
        initializedPlugin: plugin,
        dao,
      } = await loadFixture(fixture);

      // Check that Alice hasn't `UPDATE_MULTISIG_SETTINGS_PERMISSION_ID` permission on the Multisig plugin.
      expect(
        await dao.hasPermission(
          plugin.address,
          alice.address,
          UPDATE_MULTISIG_SETTINGS_PERMISSION_ID,
          []
        )
      ).to.be.false;

      // Expect Alice's `removeAddresses` call to be reverted because she hasn't `UPDATE_MULTISIG_SETTINGS_PERMISSION_ID`
      // permission on the Multisig plugin.
      await expect(
        plugin.connect(alice).removeAddresses([bob.address, carol.address])
      )
        .to.be.revertedWithCustomError(plugin, 'DaoUnauthorized')
        .withArgs(
          dao.address,
          plugin.address,
          alice.address,
          UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
        );
    });

    it('removes users from the address list and emit the `MembersRemoved` event', async () => {
      const {
        alice,
        bob,
        carol,
        initializedPlugin: plugin,
        dao,
      } = await loadFixture(fixture);

      // Grant Alice the permission to update settings.
      await dao.grant(
        plugin.address,
        alice.address,
        UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
      );

      // Check that Alice, Bob, and Carol are listed.
      expect(await plugin.isListed(alice.address)).to.equal(true);
      expect(await plugin.isListed(bob.address)).to.equal(true);
      expect(await plugin.isListed(carol.address)).to.equal(true);

      // Call `removeAddresses` as Alice to remove Bob.
      await expect(plugin.connect(alice).removeAddresses([bob.address]))
        .to.emit(plugin, 'MembersRemoved')
        .withArgs([bob.address]);

      // Check that Bob is removed while Alice and Carol remains listed.
      expect(await plugin.isListed(alice.address)).to.equal(true);
      expect(await plugin.isListed(bob.address)).to.equal(false);
      expect(await plugin.isListed(carol.address)).to.equal(true);
    });

    it('reverts if the address list would become empty', async () => {
      const {
        alice,
        initializedPlugin: plugin,
        defaultInitData,
        dao,
      } = await loadFixture(fixture);

      // Grant Alice the permission to update settings.
      await dao.grant(
        plugin.address,
        alice.address,
        UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
      );

      // Try to remove all members.
      await expect(
        plugin.connect(alice).removeAddresses(defaultInitData.members)
      )
        .to.be.revertedWithCustomError(plugin, 'MinApprovalsOutOfBounds')
        .withArgs(0, defaultInitData.settings.minApprovals);
    });

    it('reverts if the address list would become shorter than the current minimum approval parameter requires', async () => {
      const {
        alice,
        carol,
        initializedPlugin: plugin,
        defaultInitData,
        dao,
      } = await loadFixture(fixture);

      // Grant Alice the permission to update settings.
      await dao.grant(
        plugin.address,
        alice.address,
        UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
      );

      // Initially, there are 3 members and `minApprovals` is 2.
      // Remove one member, which is ok.
      await expect(plugin.connect(alice).removeAddresses([carol.address])).not
        .to.be.reverted;

      // Try to remove  another member, which will revert.
      await expect(plugin.connect(alice).removeAddresses([alice.address]))
        .to.be.revertedWithCustomError(plugin, 'MinApprovalsOutOfBounds')
        .withArgs(
          (await plugin.addresslistLength()).sub(1),
          defaultInitData.settings.minApprovals
        );
    });
  });

  // These tests ensure that overriden `createProposal` function from `IProposal`
  // successfully creates a proposal with default values(when `data` is not passed)
  // and with custom values when it's passed.
  describe('Proposal creation: IProposal Interface Function', async () => {
    let data: FixtureResult;
    beforeEach(async () => {
      data = await loadFixtureAndGrantCreatePermission();
      const {deployer, dao, initializedPlugin: plugin} = data;

      await dao.grant(
        plugin.address,
        deployer.address,
        UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
      );

      await plugin.updateMultisigSettings({
        onlyListed: false,
        minApprovals: 1,
      });

      await dao.grant(
        dao.address,
        plugin.address,
        DAO_PERMISSIONS.EXECUTE_PERMISSION_ID
      );
    });

    it('creates proposal with default values if `data` param is encoded with custom values', async () => {
      const {
        alice,
        dummyMetadata,
        dummyActions,
        initializedPlugin: plugin,
      } = data;

      const encodedParam = ethers.utils.defaultAbiCoder.encode(
        ['uint256', 'bool', 'bool'],
        [1, true, true]
      );

      const proposalId = await createProposalId(
        plugin.address,
        dummyActions,
        dummyMetadata
      );

      await plugin
        .connect(alice)
        [CREATE_PROPOSAL_SIGNATURE_IProposal](
          dummyMetadata,
          dummyActions,
          0,
          (await time.latest()) + TIME.HOUR,
          encodedParam
        );

      const proposal = await plugin.getProposal(proposalId);
      expect(proposal.allowFailureMap).to.equal(1);

      expect(await plugin.hasApproved(proposalId, alice.address)).to.be.true;
      expect(proposal.executed).to.be.true;
    });

    it('creates proposal with default values if `data` param is passed as empty', async () => {
      const {
        alice,
        dummyMetadata,
        dummyActions,
        initializedPlugin: plugin,
      } = data;

      const proposalId = await createProposalId(
        plugin.address,
        dummyActions,
        dummyMetadata
      );

      await plugin
        .connect(alice)
        [CREATE_PROPOSAL_SIGNATURE_IProposal](
          dummyMetadata,
          dummyActions,
          0,
          (await time.latest()) + TIME.HOUR,
          '0x'
        );

      const proposal = await plugin.getProposal(proposalId);
      expect(proposal.actions.length).to.equal(dummyActions.length);
      expect(proposal.allowFailureMap).to.equal(0);

      expect(await plugin.hasApproved(proposalId, alice.address)).to.be.false;
      expect(proposal.executed).to.be.false;
    });
  });

  describe('createProposal', async () => {
    let data: FixtureResult;
    beforeEach(async () => {
      data = await loadFixtureAndGrantCreatePermission();
    });

    it('reverts if permission is not given', async () => {
      const {deployer, dao, initializedPlugin: plugin} = data;
      await dao.revoke(plugin.address, ANY_ADDR, CREATE_PROPOSAL_PERMISSION_ID);

      await expect(
        plugin[CREATE_PROPOSAL_SIGNATURE](
          '0x',
          [],
          0,
          false,
          false,
          0,
          await time.latest()
        )
      )
        .to.be.revertedWithCustomError(plugin, 'DaoUnauthorized')
        .withArgs(
          dao.address,
          plugin.address,
          deployer.address,
          CREATE_PROPOSAL_PERMISSION_ID
        );
    });

    it('generates the proposal id by hashing the actions + metadata', async () => {
      const {
        alice,
        initializedPlugin: plugin,
        dummyMetadata,
        dummyActions,
        defaultInitData,
      } = data;

      const proposalId = await createProposalId(
        plugin.address,
        dummyActions,
        dummyMetadata
      );

      // Create a proposal as Alice.
      const endDate = (await time.latest()) + TIME.HOUR;

      await plugin
        .connect(alice)
        [CREATE_PROPOSAL_SIGNATURE](
          dummyMetadata,
          dummyActions,
          0,
          false,
          false,
          0,
          endDate
        );

      // Check that proposal exists
      const proposal = await plugin.getProposal(proposalId);
      expect(proposal.actions.length).to.equal(dummyActions.length);
      expect(proposal.parameters.minApprovals).to.equal(
        defaultInitData.settings.minApprovals
      );
    });

    it('emits the `ProposalCreated` event', async () => {
      const {alice, initializedPlugin: plugin, dummyMetadata} = data;

      // Create a proposal as Alice and check the event arguments.
      const startDate = (await time.latest()) + TIME.MINUTE;
      const endDate = startDate + TIME.HOUR;
      const expectedProposalId = await createProposalId(
        plugin.address,
        [],
        dummyMetadata
      );
      await expect(
        plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            [],
            0,
            false,
            false,
            startDate,
            endDate
          )
      )
        .to.emit(plugin, 'ProposalCreated')
        .withArgs(
          expectedProposalId,
          alice.address,
          startDate,
          endDate,
          dummyMetadata,
          [],
          0
        );
    });

    it('reverts if the multisig settings have been changed in the same block', async () => {
      const {alice, initializedPlugin: plugin, dao} = data;

      // Grant Alice the permission to update the settings.
      await dao.grant(
        plugin.address,
        alice.address,
        UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
      );

      const newSettings = {
        onlyListed: false,
        minApprovals: 1,
      };

      /* Make two calls to update the settings in the same block. */
      // Disable auto-mining so that both proposals end up in the same block.
      await ethers.provider.send('evm_setAutomine', [false]);
      // Update #1
      await plugin.connect(alice).updateMultisigSettings(newSettings);
      // Update #2
      await plugin.connect(alice).updateMultisigSettings(newSettings);
      // Re-enable auto-mining so that the remaining tests run normally.
      await ethers.provider.send('evm_setAutomine', [true]);
    });

    it('reverts if the multisig settings have been changed in the same block via the proposals process', async () => {
      const {
        alice,
        uninitializedPlugin: plugin,
        dummyMetadata,
        dao,
        defaultInitData,
      } = data;
      await plugin.initialize(
        dao.address,
        [alice.address],
        {
          onlyListed: true,
          minApprovals: 1,
        },
        defaultInitData.targetConfig,
        defaultInitData.metadata
      );

      // Grant permissions between the DAO and the plugin.
      await dao.grant(
        plugin.address,
        dao.address,
        UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
      );
      await dao.grant(
        dao.address,
        plugin.address,
        DAO_PERMISSIONS.EXECUTE_PERMISSION_ID
      );

      // Create an action calling `updateMultisigSettings`.
      const updateMultisigSettingsAction = {
        to: plugin.address,
        value: 0,
        data: plugin.interface.encodeFunctionData('updateMultisigSettings', [
          {
            onlyListed: false,
            minApprovals: 1,
          },
        ]),
      };

      /* Create two proposals to update the settings in the same block. */
      const endDate = (await time.latest()) + TIME.HOUR;

      // Disable auto-mining so that both proposals end up in the same block.
      await ethers.provider.send('evm_setAutomine', [false]);

      // Create and execute proposal #1 calling `updateMultisigSettings`.
      await plugin.connect(alice)[CREATE_PROPOSAL_SIGNATURE](
        dummyMetadata,
        [updateMultisigSettingsAction],
        0,
        true, // approve
        true, // execute
        0,
        endDate
      );

      // Try to call update the settings a second time.
      await expect(
        plugin.connect(alice)[CREATE_PROPOSAL_SIGNATURE](
          dummyMetadata,
          [updateMultisigSettingsAction],
          0,
          false, // approve
          false, // execute
          0,
          endDate
        )
      )
        .to.revertedWithCustomError(plugin, 'ProposalCreationForbidden')
        .withArgs(alice.address);

      // Re-enable auto-mining so that the remaining tests run normally.
      await ethers.provider.send('evm_setAutomine', [true]);
    });

    describe('`onlyListed` is set to `false`', async () => {
      it('creates a proposal when an unlisted accounts is calling', async () => {
        const {
          alice,
          dave,
          initializedPlugin: plugin,
          dao,
          dummyMetadata,
        } = data;

        // Grant Alice the permission to update settings.
        await dao.grant(
          plugin.address,
          alice.address,
          UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
        );

        // As Alice, set `onlyListed` to `false`.
        await plugin.connect(alice).updateMultisigSettings({
          minApprovals: 2,
          onlyListed: false,
        });

        // Create a proposal as Dave (who is not listed).
        const startDate = (await time.latest()) + TIME.MINUTE;
        const endDate = startDate + TIME.HOUR;

        const expectedProposalId = await createProposalId(
          plugin.address,
          [],
          dummyMetadata
        );

        await expect(
          plugin
            .connect(dave) // Dave is not listed.
            [CREATE_PROPOSAL_SIGNATURE](
              dummyMetadata,
              [],
              0,
              false,
              false,
              startDate,
              endDate
            )
        )
          .to.emit(plugin, 'ProposalCreated')
          .withArgs(
            expectedProposalId,
            dave.address,
            startDate,
            endDate,
            dummyMetadata,
            [],
            0
          );
      });
    });

    describe('`onlyListed` is set to `true`', async () => {
      it('reverts if the caller is not listed and only listed accounts can create proposals', async () => {
        const {
          dao,
          dave,
          initializedPlugin: plugin,
          dummyMetadata,
          dummyActions,
        } = data;

        // Try to create a proposal as Dave (who is not listed), which should revert.
        const endDate = (await time.latest()) + TIME.HOUR;
        await expect(
          plugin
            .connect(dave) // Dave is not listed.
            [CREATE_PROPOSAL_SIGNATURE](
              dummyMetadata,
              dummyActions,
              0,
              false,
              false,
              0,
              endDate
            )
        )
          .to.be.revertedWithCustomError(plugin, 'DaoUnauthorized')
          .withArgs(
            dao.address,
            plugin.address,
            dave.address,
            CREATE_PROPOSAL_PERMISSION_ID
          );
      });

      it('reverts if caller is not listed in the current block although she was listed in the last block', async () => {
        const {
          alice,
          carol,
          dave,
          initializedPlugin: plugin,
          dao,
          dummyMetadata,
          dummyActions,
        } = data;

        // Grant Alice the permission to update settings.
        await dao.grant(
          plugin.address,
          alice.address,
          UPDATE_MULTISIG_SETTINGS_PERMISSION_ID
        );

        const endDate = (await time.latest()) + TIME.HOUR;

        // Disable auto-mining so that all subsequent transactions end up in the same block.
        await ethers.provider.send('evm_setAutomine', [false]);
        const expectedSnapshotBlockNumber = (
          await ethers.provider.getBlock('latest')
        ).number;

        // Transaction 1 & 2: Add Dave and remove Carol.
        const tx1 = await plugin.connect(alice).addAddresses([dave.address]);
        const tx2 = await plugin
          .connect(alice)
          .removeAddresses([carol.address]);

        // Transaction 3: Expect the proposal creation to fail for Carol because she was removed as a member in transaction 2.

        await expect(
          plugin
            .connect(carol)
            [CREATE_PROPOSAL_SIGNATURE](
              dummyMetadata,
              dummyActions,
              0,
              false,
              false,
              0,
              endDate
            )
        )
          .to.be.revertedWithCustomError(plugin, 'DaoUnauthorized')
          .withArgs(
            dao.address,
            plugin.address,
            carol.address,
            CREATE_PROPOSAL_PERMISSION_ID
          );

        // Transaction 4: Create the proposal as Dave
        const tx4 = await plugin
          .connect(dave)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        // Check the listed members before the block is mined.
        expect(await plugin.isListed(carol.address)).to.equal(true);
        expect(await plugin.isListed(dave.address)).to.equal(false);

        // Mine the block
        await ethers.provider.send('evm_mine', []);
        const minedBlockNumber = (await ethers.provider.getBlock('latest'))
          .number;

        // Expect all transaction receipts to be in the same block after the snapshot block.
        expect((await tx1.wait()).blockNumber).to.equal(minedBlockNumber);
        expect((await tx2.wait()).blockNumber).to.equal(minedBlockNumber);
        expect((await tx4.wait()).blockNumber).to.equal(minedBlockNumber);
        expect(minedBlockNumber).to.equal(expectedSnapshotBlockNumber + 1);

        // Expect the listed member to have changed.
        expect(await plugin.isListed(carol.address)).to.equal(false);
        expect(await plugin.isListed(dave.address)).to.equal(true);

        // Check the `ProposalCreatedEvent` for the creator and proposalId.
        const event = findEvent<ProposalCreatedEvent>(
          await tx4.wait(),
          'ProposalCreated'
        );
        expect(event.args.proposalId).to.equal(id);
        expect(event.args.creator).to.equal(dave.address);

        // Check that the snapshot block stored in the proposal struct.
        const proposal = await plugin.getProposal(id);
        expect(proposal.parameters.snapshotBlock).to.equal(
          expectedSnapshotBlockNumber
        );

        // Re-enable auto-mining so that the remaining tests run normally.
        await ethers.provider.send('evm_setAutomine', [true]);
      });
    });

    it('creates a proposal successfully and does not approve if not specified', async () => {
      const {
        alice,
        bob,
        initializedPlugin: plugin,
        defaultInitData,
        dummyMetadata,
      } = data;

      // Create a proposal (ID 0) as Alice but don't approve on creation.
      const startDate = (await time.latest()) + TIME.MINUTE;
      const endDate = startDate + TIME.HOUR;
      const allowFailureMap = 0;
      await time.setNextBlockTimestamp(startDate);
      const id = await createProposalId(plugin.address, [], dummyMetadata);

      const approveProposal = false;

      await expect(
        plugin.connect(alice)[CREATE_PROPOSAL_SIGNATURE](
          dummyMetadata,
          [],
          allowFailureMap,
          approveProposal, // false
          false,
          startDate,
          endDate
        )
      )
        .to.emit(plugin, 'ProposalCreated')
        .withArgs(id, alice.address, startDate, endDate, dummyMetadata, [], 0);

      const latestBlock = await ethers.provider.getBlock('latest');

      // Check that the proposal was created as expected and has 0 approvals.
      const proposal = await plugin.getProposal(id);
      expect(proposal.executed).to.equal(false);
      expect(proposal.allowFailureMap).to.equal(0);
      expect(proposal.parameters.snapshotBlock).to.equal(
        latestBlock.number - 1
      );
      expect(proposal.parameters.minApprovals).to.equal(
        defaultInitData.settings.minApprovals
      );
      expect(proposal.parameters.startDate).to.equal(startDate);
      expect(proposal.parameters.endDate).to.equal(endDate);
      expect(proposal.actions.length).to.equal(0);
      expect(proposal.approvals).to.equal(0);

      // Check that Alice hasn't approved the proposal yet.
      expect(await plugin.canApprove(id, alice.address)).to.be.true;
      // Check that, e.g., Bob hasn't approved the proposal yet.
      expect(await plugin.canApprove(id, bob.address)).to.be.true;
    });

    it('creates a proposal successfully and approves if specified', async () => {
      const {
        alice,
        bob,
        initializedPlugin: plugin,
        defaultInitData,
        dummyMetadata,
      } = data;

      // Create a proposal as Alice and approve on creation.
      const startDate = (await time.latest()) + TIME.MINUTE;
      const endDate = startDate + TIME.HOUR;
      const allowFailureMap = 1;
      const approveProposal = true;

      await time.setNextBlockTimestamp(startDate);

      const id = await createProposalId(plugin.address, [], dummyMetadata);
      await expect(
        plugin.connect(alice)[CREATE_PROPOSAL_SIGNATURE](
          dummyMetadata,
          [],
          allowFailureMap,
          approveProposal, // true
          false,
          startDate,
          endDate
        )
      )
        .to.emit(plugin, 'ProposalCreated')
        .withArgs(
          id,
          alice.address,
          startDate,
          endDate,
          dummyMetadata,
          [],
          allowFailureMap
        )
        .to.emit(plugin, MULTISIG_EVENTS.Approved)
        .withArgs(id, alice.address);

      const latestBlock = await ethers.provider.getBlock('latest');

      // Check that the proposal was created as expected and has 1 approval.
      const proposal = await plugin.getProposal(id);
      expect(proposal.executed).to.equal(false);
      expect(proposal.allowFailureMap).to.equal(allowFailureMap);
      expect(proposal.parameters.snapshotBlock).to.equal(
        latestBlock.number - 1
      );
      expect(proposal.parameters.minApprovals).to.equal(
        defaultInitData.settings.minApprovals
      );
      expect(proposal.parameters.startDate).to.equal(startDate);
      expect(proposal.parameters.endDate).to.equal(endDate);
      expect(proposal.actions.length).to.equal(0);
      expect(proposal.approvals).to.equal(1);

      // Check that Alice has approved the proposal already.
      expect(await plugin.canApprove(id, alice.address)).to.be.false;
      // Check that, e.g., Bob hasn't approved the proposal yet.
      expect(await plugin.canApprove(id, bob.address)).to.be.true;
    });

    it('reverts if startDate < now', async () => {
      const {
        alice,
        initializedPlugin: plugin,
        dummyMetadata,
        dummyActions,
      } = data;

      // Set the clock to the start date.
      const startDate = (await time.latest()) + TIME.MINUTE;
      await time.setNextBlockTimestamp(startDate);

      //  Try to create a proposal as Alice where the start date lies in the past.
      const startDateInThePast = startDate - 1;
      const endDate = startDate + TIME.HOUR;
      await expect(
        plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            true,
            false,
            startDateInThePast,
            endDate
          )
      )
        .to.be.revertedWithCustomError(plugin, 'DateOutOfBounds')
        .withArgs(startDate, startDateInThePast);
    });

    it('reverts if endDate < startDate', async () => {
      const {
        alice,
        initializedPlugin: plugin,
        dummyMetadata,
        dummyActions,
      } = data;

      // Try to create a proposal as Alice where the end date is before the start date
      const startDate = (await time.latest()) + TIME.MINUTE;
      const endDate = startDate - 1; // endDate < startDate
      await expect(
        plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            true,
            false,
            startDate,
            endDate
          )
      )
        .to.be.revertedWithCustomError(plugin, 'DateOutOfBounds')
        .withArgs(startDate, endDate);
    });
  });

  context('Approving and executing proposals', async () => {
    let data: FixtureResult;
    beforeEach(async () => {
      data = await loadFixtureAndGrantCreatePermission();
    });

    describe('canApprove', async () => {
      it('returns `false` if the proposal is already executed', async () => {
        const {
          alice,
          bob,
          carol,
          initializedPlugin: plugin,
          dao,
          dummyMetadata,
          dummyActions,
        } = data;

        const endDate = (await time.latest()) + TIME.HOUR;
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        await dao.grant(
          dao.address,
          plugin.address,
          DAO_PERMISSIONS.EXECUTE_PERMISSION_ID
        );

        // Check that Carol can approve.
        expect(await plugin.canApprove(id, carol.address)).to.be.true;

        // Approve with Alice.
        await plugin.connect(alice).approve(id, false);
        // Approve and execute with Bob.
        await plugin.connect(bob).approve(id, true);

        // Check that the proposal got executed.
        expect((await plugin.getProposal(id)).executed).to.be.true;

        // Check that Carol cannot approve the executed proposal anymore.
        expect(await plugin.canApprove(id, carol.address)).to.be.false;
      });

      it('returns `false` if the approver is not listed', async () => {
        const {
          alice,
          dave,
          initializedPlugin: plugin,
          dummyMetadata,
          dummyActions,
        } = data;

        // Create a proposal as Alice.
        const endDate = (await time.latest()) + TIME.HOUR;
        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );
        const id = 0;

        // Check that Dave who is not listed cannot approve.
        expect(await plugin.isListed(dave.address)).to.be.false;
        expect(await plugin.canApprove(id, dave.address)).to.be.false;
      });

      it('returns `false` if the approver has already approved', async () => {
        const {
          alice,
          initializedPlugin: plugin,
          dummyMetadata,
          dummyActions,
        } = data;

        const endDate = (await time.latest()) + TIME.HOUR;

        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        await plugin.connect(alice).approve(id, false);
        expect(await plugin.canApprove(id, alice.address)).to.be.false;
      });

      it('returns `true` if the approver is listed', async () => {
        const {
          alice,
          initializedPlugin: plugin,
          dummyMetadata,
          dummyActions,
        } = data;

        const endDate = (await time.latest()) + TIME.HOUR;

        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        expect(await plugin.canApprove(id, alice.address)).to.be.true;
      });

      it("returns `false` if the proposal hasn't started yet", async () => {
        const {
          alice,
          initializedPlugin: plugin,
          dummyMetadata,
          dummyActions,
        } = data;

        const startDate = (await time.latest()) + TIME.MINUTE;
        const endDate = startDate + TIME.HOUR;

        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            startDate,
            endDate
          );

        expect(await plugin.canApprove(id, alice.address)).to.be.false;

        await time.increaseTo(startDate);

        expect(await plugin.canApprove(id, alice.address)).to.be.true;
      });

      it('returns `false` if the proposal has ended', async () => {
        const {
          alice,
          initializedPlugin: plugin,
          dummyMetadata,
          dummyActions,
        } = data;

        const endDate = (await time.latest()) + TIME.HOUR;

        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        expect(await plugin.canApprove(id, alice.address)).to.be.true;

        await time.increaseTo(endDate + 1);

        expect(await plugin.canApprove(id, alice.address)).to.be.false;
      });
    });

    describe('hasApproved', async () => {
      it("returns `false` if user hasn't approved yet", async () => {
        const {
          alice,
          initializedPlugin: plugin,
          dummyMetadata,
          dummyActions,
        } = data;

        const endDate = (await time.latest()) + TIME.HOUR;

        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        expect(await plugin.hasApproved(id, alice.address)).to.be.false;
      });

      it('returns `true` if user has approved', async () => {
        const {
          alice,
          initializedPlugin: plugin,
          dummyMetadata,
          dummyActions,
        } = data;

        const endDate = (await time.latest()) + TIME.HOUR;
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        await plugin.connect(alice).approve(id, false);
        expect(await plugin.hasApproved(id, alice.address)).to.be.true;
      });
    });

    describe('approve', async () => {
      it('reverts when approving multiple times', async () => {
        const {
          alice,
          initializedPlugin: plugin,
          dummyMetadata,
          dummyActions,
        } = data;

        const endDate = (await time.latest()) + TIME.HOUR;

        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );
        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        await plugin.connect(alice).approve(id, true);

        // Try to vote again
        await expect(plugin.connect(alice).approve(id, true))
          .to.be.revertedWithCustomError(plugin, 'ApprovalCastForbidden')
          .withArgs(id, alice.address);
      });

      it('reverts if minimal approval is not met yet', async () => {
        const {
          alice,
          initializedPlugin: plugin,
          dummyMetadata,
          dummyActions,
          dao,
        } = data;

        const endDate = (await time.latest()) + TIME.HOUR;

        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        // Grant the plugin `EXECUTE_PERMISSION_ID` permission on the DAO.
        await dao.grant(
          dao.address,
          plugin.address,
          DAO_PERMISSIONS.EXECUTE_PERMISSION_ID
        );

        // Try to execute the proposals although `minApprovals` has not been reached yet.
        const proposal = await plugin.getProposal(id);
        expect(proposal.approvals).to.eq(0);
        await expect(plugin.connect(alice).execute(id))
          .to.be.revertedWithCustomError(plugin, 'ProposalExecutionForbidden')
          .withArgs(id);
      });

      it('approves with the caller address', async () => {
        const {
          alice,
          initializedPlugin: plugin,
          dummyMetadata,
          dummyActions,
        } = data;

        const endDate = (await time.latest()) + TIME.HOUR;

        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        // Check that there are 0 approvals yet.
        expect((await plugin.getProposal(id)).approvals).to.equal(0);

        // Approve the proposal as Alice.
        const tx = await plugin.connect(alice).approve(id, false);

        // Check the `Approved` event and make sure that Alice is emitted as the approver.
        const event = findEvent<ApprovedEvent>(await tx.wait(), 'Approved');
        expect(event.args.proposalId).to.eq(id);
        expect(event.args.approver).to.eq(alice.address);

        // Check that the approval was counted.
        expect((await plugin.getProposal(id)).approvals).to.equal(1);
      });

      it("reverts if the proposal hasn't started yet", async () => {
        const {
          alice,
          initializedPlugin: plugin,
          dummyMetadata,
          dummyActions,
        } = data;

        // Create a proposal as Alice that didn't started yet.
        const startDate = (await time.latest()) + TIME.MINUTE;
        const endDate = startDate + TIME.HOUR;
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            startDate,
            endDate
          );

        // Try to approve the proposal as Alice although being before the start date.
        await expect(plugin.connect(alice).approve(id, false))
          .to.be.revertedWithCustomError(plugin, 'ApprovalCastForbidden')
          .withArgs(id, alice.address);

        // Advance to the start date.
        await time.increaseTo(startDate);

        // Approve as Alice and check that this doesn't revert.
        await expect(plugin.connect(alice).approve(id, false)).not.to.be
          .reverted;
      });

      it('reverts if the proposal has ended', async () => {
        const {
          alice,
          initializedPlugin: plugin,
          dummyMetadata,
          dummyActions,
        } = data;

        // Create a proposal as Alice that starts now.
        const startDate = (await time.latest()) + TIME.MINUTE;
        const endDate = startDate + TIME.HOUR;
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        // Advance time after the end date.
        await time.increaseTo(endDate + 1);

        await expect(plugin.connect(alice).approve(id, false))
          .to.be.revertedWithCustomError(plugin, 'ApprovalCastForbidden')
          .withArgs(id, alice.address);
      });
    });

    describe('canExecute', async () => {
      it('returns `false` if the proposal has not reached the minimum approval yet', async () => {
        const {
          alice,
          initializedPlugin: plugin,
          dummyMetadata,
          dummyActions,
        } = data;

        // Create a proposal as Alice.
        const endDate = (await time.latest()) + TIME.HOUR;
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        // Check that `minApprovals` isn't met yet.
        const proposal = await plugin.getProposal(id);
        expect(proposal.approvals).to.be.lt(proposal.parameters.minApprovals);

        // Check that the proposal can not be executed.
        expect(await plugin.canExecute(id)).to.be.false;
      });

      it('returns `false` if the proposal is already executed', async () => {
        const {
          alice,
          bob,
          initializedPlugin: plugin,
          dao,
          dummyMetadata,
          dummyActions,
        } = data;

        // Create a proposal as Alice.
        const endDate = (await time.latest()) + TIME.HOUR;
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );
        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        // Grant the plugin `EXECUTE_PERMISSION_ID` permission on the DAO.
        await dao.grant(
          dao.address,
          plugin.address,
          DAO_PERMISSIONS.EXECUTE_PERMISSION_ID
        );

        // Approve as Alice.
        await plugin.connect(alice).approve(id, false);
        // Approve and execute as Bob.
        await plugin.connect(bob).approve(id, true);

        // Check that the proposal got executed.
        expect((await plugin.getProposal(id)).executed).to.be.true;

        // Check that it cannot be executed again.
        expect(await plugin.canExecute(id)).to.be.false;
      });

      it('returns `true` if the proposal can be executed', async () => {
        const {
          alice,
          bob,
          initializedPlugin: plugin,
          dummyMetadata,
          dummyActions,
        } = data;

        const endDate = (await time.latest()) + TIME.HOUR;
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        await plugin.connect(alice).approve(id, false);
        await plugin.connect(bob).approve(id, false);

        expect((await plugin.getProposal(id)).executed).to.be.false;
        expect(await plugin.canExecute(id)).to.be.true;
      });

      it("returns `false` if the proposal hasn't started yet", async () => {
        const {
          alice,
          bob,
          carol,
          initializedPlugin: plugin,
          dummyMetadata,
          dummyActions,
        } = data;

        const startDate = (await time.latest()) + TIME.MINUTE;
        const endDate = startDate + TIME.HOUR;
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            startDate,
            endDate
          );

        expect(await plugin.canExecute(id)).to.be.false;

        await time.increaseTo(startDate);
        await plugin.connect(alice).approve(id, false);
        await plugin.connect(bob).approve(id, false);
        await plugin.connect(carol).approve(id, false);

        expect(await plugin.canExecute(id)).to.be.true;
      });

      it('returns `false` if the proposal has ended', async () => {
        const {
          alice,
          bob,
          carol,
          initializedPlugin: plugin,
          dummyMetadata,
          dummyActions,
        } = data;

        const endDate = (await time.latest()) + TIME.HOUR;
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        await plugin.connect(alice).approve(id, false);
        await plugin.connect(bob).approve(id, false);
        await plugin.connect(carol).approve(id, false);

        expect(await plugin.canExecute(id)).to.be.true;

        await time.increaseTo(endDate + 1);

        expect(await plugin.canExecute(id)).to.be.false;
      });
    });

    describe('execute', async () => {
      it('reverts if the minimum approval is not met', async () => {
        const {
          alice,
          initializedPlugin: plugin,
          dao,
          dummyMetadata,
          dummyActions,
        } = data;

        // Create a proposal as Alice.
        const endDate = (await time.latest()) + TIME.HOUR;
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        // Grant the plugin `EXECUTE_PERMISSION_ID` permission on the DAO.
        await dao.grant(
          dao.address,
          plugin.address,
          DAO_PERMISSIONS.EXECUTE_PERMISSION_ID
        );

        // Check that proposal cannot be executed if the minimum approval is not met yet.
        await expect(plugin.execute(id))
          .to.be.revertedWithCustomError(plugin, 'ProposalExecutionForbidden')
          .withArgs(id);
      });

      it('executes if the minimum approval is met', async () => {
        const {
          alice,
          bob,
          initializedPlugin: plugin,
          defaultInitData,
          dao,
          dummyMetadata,
          dummyActions,
        } = data;

        // Create a proposal as Alice.
        const endDate = (await time.latest()) + TIME.HOUR;
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        // Grant the plugin `EXECUTE_PERMISSION_ID` permission on the DAO.
        await dao.grant(
          dao.address,
          plugin.address,
          DAO_PERMISSIONS.EXECUTE_PERMISSION_ID
        );

        // Approve with Alice and Bob.
        await plugin.connect(alice).approve(id, false);
        await plugin.connect(bob).approve(id, false);

        // Check that the `minApprovals` threshold is met.
        const proposal = await plugin.getProposal(id);
        expect(proposal.parameters.minApprovals).to.equal(
          defaultInitData.settings.minApprovals
        );
        expect(proposal.approvals).to.be.eq(
          defaultInitData.settings.minApprovals
        );

        // Check that the proposal can be executed.
        expect(await plugin.canExecute(id)).to.be.true;

        // Check that it executes.
        await expect(plugin.execute(id)).not.to.be.reverted;
      });

      it('executes if the minimum approval is met and can be called by an unlisted accounts', async () => {
        const {
          alice,
          bob,
          dave,
          initializedPlugin: plugin,
          defaultInitData,
          dao,
          dummyMetadata,
          dummyActions,
        } = data;

        const endDate = (await time.latest()) + TIME.HOUR;
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        await dao.grant(
          dao.address,
          plugin.address,
          DAO_PERMISSIONS.EXECUTE_PERMISSION_ID
        );

        await plugin.connect(alice).approve(id, false);
        await plugin.connect(bob).approve(id, false);

        const proposal = await plugin.getProposal(id);

        expect(proposal.parameters.minApprovals).to.equal(
          defaultInitData.settings.minApprovals
        );
        expect(proposal.approvals).to.be.eq(
          defaultInitData.settings.minApprovals
        );

        expect(await plugin.canExecute(id)).to.be.true;
        expect(await plugin.isListed(dave.address)).to.be.false; // Dave is not listed
        await expect(plugin.connect(dave).execute(id)).not.to.be.reverted;
      });

      it('executes if the minimum approval is met when multisig with the `tryExecution` option', async () => {
        const {
          alice,
          bob,
          carol,
          initializedPlugin: plugin,
          dao,
          dummyMetadata,
          dummyActions,
        } = data;

        // Create a proposal as Alice.
        const endDate = (await time.latest()) + TIME.HOUR;
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        // Grant the plugin `EXECUTE_PERMISSION_ID` permission on the DAO.
        await dao.grant(
          dao.address,
          plugin.address,
          DAO_PERMISSIONS.EXECUTE_PERMISSION_ID
        );

        // Approve and try execution as Alice although the `minApprovals` threshold is not met yet.
        let tx = await plugin.connect(alice).approve(id, true);
        let rc = await tx.wait();
        expect(() =>
          findEventTopicLog<ExecutedEvent>(
            rc,
            DAO__factory.createInterface(),
            'Executed'
          )
        ).to.throw(
          `Event "Executed" could not be found in transaction ${tx.hash}.`
        );

        expect(await plugin.canExecute(id)).to.equal(false);

        // Approve but do not try execution as Bob although the `minApprovals` threshold is reached now.
        tx = await plugin.connect(bob).approve(id, false);
        rc = await tx.wait();
        expect(() =>
          findEventTopicLog<ExecutedEvent>(
            rc,
            DAO__factory.createInterface(),
            'Executed'
          )
        ).to.throw(
          `Event "Executed" could not be found in transaction ${tx.hash}.`
        );

        // Approve and try execution as Carol while `minApprovals` threshold is reached already.
        tx = await plugin.connect(carol).approve(id, true);

        // Check that the proposal got executed by checking the `Executed` event emitted by the DAO.
        {
          const event = findEventTopicLog<ExecutedEvent>(
            await tx.wait(),
            DAO__factory.createInterface(),
            'Executed'
          );

          expect(event.args.actor).to.equal(plugin.address);
          expect(event.args.callId).to.equal(ethers.utils.hexZeroPad(id, 32));
          expect(event.args.actions.length).to.equal(1);
          expect(event.args.actions[0].to).to.equal(dummyActions[0].to);
          expect(event.args.actions[0].value).to.equal(dummyActions[0].value);
          expect(event.args.actions[0].data).to.equal(dummyActions[0].data);
          expect(event.args.execResults).to.deep.equal(['0x']);

          const prop = await plugin.getProposal(id);
          expect(prop.executed).to.equal(true);
        }

        // Check that the proposal got executed by checking the `ProposalExecuted` event emitted by the plugin.
        {
          const event = findEvent<ProposalExecutedEvent>(
            await tx.wait(),
            'ProposalExecuted'
          );
          expect(event.args.proposalId).to.equal(id);
        }

        // Try executing it again.
        await expect(plugin.execute(id))
          .to.be.revertedWithCustomError(plugin, 'ProposalExecutionForbidden')
          .withArgs(id);
      });

      it('emits the `ProposalExecuted` and `Executed` events', async () => {
        const {
          alice,
          bob,
          initializedPlugin: plugin,
          dao,
          dummyMetadata,
          dummyActions,
        } = data;

        // Create a proposal as Alice.
        const endDate = (await time.latest()) + TIME.HOUR;
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        // Grant the plugin `EXECUTE_PERMISSION_ID` on the DAO.
        await dao.grant(
          dao.address,
          plugin.address,
          DAO_PERMISSIONS.EXECUTE_PERMISSION_ID
        );

        // Approve the proposal as Alice and Bob.
        await plugin.connect(alice).approve(id, false);
        await plugin.connect(bob).approve(id, false);

        // Execute the proposal and check that the `Executed` and `ProposalExecuted` event is emitted
        // and that the `Approved` event is not emitted.
        await expect(plugin.connect(alice).execute(id))
          .to.emit(dao, 'Executed')
          .to.emit(plugin, 'ProposalExecuted')
          .to.not.emit(plugin, 'Approved');
      });

      it('emits the `Approved`, `ProposalExecuted`, and `Executed` events if execute is called inside the `approve` method', async () => {
        const {
          alice,
          bob,
          initializedPlugin: plugin,
          dao,
          dummyMetadata,
          dummyActions,
        } = data;

        // Create a proposal as Alice.
        const endDate = (await time.latest()) + TIME.HOUR;
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        // Grant the plugin `EXECUTE_PERMISSION_ID` permission on the DAO.
        await dao.grant(
          dao.address,
          plugin.address,
          DAO_PERMISSIONS.EXECUTE_PERMISSION_ID
        );

        // Approve the proposal as Alice.
        await plugin.connect(alice).approve(id, false);

        // Approve and execute the proposal as Bob and check that the `Executed`, `ProposalExecuted`, and `Approved`
        // event is not emitted.
        await expect(plugin.connect(bob).approve(id, true))
          .to.emit(dao, 'Executed')
          .to.emit(plugin, 'ProposalExecuted')
          .to.emit(plugin, 'Approved');
      });

      it("reverts if the proposal hasn't started yet", async () => {
        const {
          alice,
          bob,
          initializedPlugin: plugin,
          dao,
          dummyMetadata,
          dummyActions,
        } = data;

        // Create a proposal as Alice.
        const startDate = (await time.latest()) + TIME.MINUTE;
        const endDate = startDate + TIME.HOUR;
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            startDate,
            endDate
          );

        // Grant the plugin `EXECUTE_PERMISSION_ID` permission on the DAO.
        await dao.grant(
          dao.address,
          plugin.address,
          DAO_PERMISSIONS.EXECUTE_PERMISSION_ID
        );

        // Try to execute the proposal before the start date.
        await expect(plugin.execute(id))
          .to.be.revertedWithCustomError(plugin, 'ProposalExecutionForbidden')
          .withArgs(id);

        // Advance time to the start date.
        await time.increaseTo(startDate);

        // Approve the proposal as Alice and Bob.
        await plugin.connect(alice).approve(id, false);
        await plugin.connect(bob).approve(id, false);

        // Execute the proposal.
        await expect(plugin.execute(id)).not.to.be.reverted;
      });

      it('reverts if the proposal has ended', async () => {
        const {
          alice,
          bob,
          initializedPlugin: plugin,
          dummyMetadata,
          dummyActions,
        } = data;

        // Create a proposal as Alice.
        const startDate = (await time.latest()) + TIME.MINUTE;
        const endDate = startDate + TIME.HOUR;
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        // Approve the proposal but do not execute yet.
        await plugin.connect(alice).approve(id, false);
        await plugin.connect(bob).approve(id, false);

        // Advance time after the end date
        await time.increase(endDate + 1);

        // Try to execute the proposal after the end date.
        await expect(
          plugin.connect(bob).execute(id)
        ).to.be.revertedWithCustomError(plugin, 'ProposalExecutionForbidden');
      });

      it('executes target with delegate call', async () => {
        const {alice, bob, dummyMetadata, dummyActions, deployer, dao} = data;

        let {initializedPlugin: plugin} = data;

        const executorFactory = new CustomExecutorMock__factory(deployer);
        const executor = await executorFactory.deploy();

        const abiA = CustomExecutorMock__factory.abi;
        const abiB = Multisig__factory.abi;
        // @ts-ignore
        const mergedABI = abiA.concat(abiB);

        await dao.grant(
          plugin.address,
          deployer.address,
          SET_TARGET_CONFIG_PERMISSION_ID
        );

        await plugin.connect(deployer).setTargetConfig({
          target: executor.address,
          operation: Operation.delegatecall,
        });

        plugin = (await ethers.getContractAt(
          mergedABI,
          plugin.address
        )) as Multisig;

        const endDate = (await time.latest()) + TIME.HOUR;
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin.connect(alice)[CREATE_PROPOSAL_SIGNATURE](
          dummyMetadata,
          dummyActions,
          1,
          true, // approve right away.
          false,
          0,
          endDate
        );

        await expect(plugin.connect(bob).approve(id, true))
          .to.emit(plugin, 'ExecutedCustom')
          .to.emit(plugin, 'ProposalExecuted');
      });

      it('can not execute if execute permission is not granted', async () => {
        const {
          alice,
          bob,
          initializedPlugin: plugin,
          defaultInitData,
          dao,
          dummyMetadata,
          dummyActions,
        } = data;

        // Create a proposal as Alice.
        const endDate = (await time.latest()) + TIME.HOUR;
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        // Grant the plugin `EXECUTE_PERMISSION_ID` permission on the DAO.
        await dao.grant(
          dao.address,
          plugin.address,
          DAO_PERMISSIONS.EXECUTE_PERMISSION_ID
        );

        // Approve with Alice and Bob.
        await plugin.connect(alice).approve(id, false);
        await plugin.connect(bob).approve(id, false);

        // Check that the `minApprovals` threshold is met.
        const proposal = await plugin.getProposal(id);
        expect(proposal.parameters.minApprovals).to.equal(
          defaultInitData.settings.minApprovals
        );
        expect(proposal.approvals).to.be.eq(
          defaultInitData.settings.minApprovals
        );

        // Check that the proposal can be executed.
        expect(await plugin.canExecute(id)).to.be.true;

        // Revoke execute permission from ANY_ADDR
        await dao.revoke(
          plugin.address,
          ANY_ADDR,
          EXECUTE_PROPOSAL_PERMISSION_ID
        );

        // Check that it executes.
        await expect(plugin.connect(alice).execute(id))
          .to.be.revertedWithCustomError(plugin, 'DaoUnauthorized')
          .withArgs(
            dao.address,
            plugin.address,
            alice.address,
            EXECUTE_PROPOSAL_PERMISSION_ID
          );
      });

      it.only('records approve correctly without execting when tryExecution is selected & execute permission is not granted', async () => {
        const {
          alice,
          bob,
          initializedPlugin: plugin,
          defaultInitData,
          dao,
          dummyMetadata,
          dummyActions,
        } = data;

        // Create a proposal as Alice.
        const endDate = (await time.latest()) + TIME.HOUR;
        const id = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        await plugin
          .connect(alice)
          [CREATE_PROPOSAL_SIGNATURE](
            dummyMetadata,
            dummyActions,
            0,
            false,
            false,
            0,
            endDate
          );

        // Grant the plugin `EXECUTE_PERMISSION_ID` permission on the DAO.
        await dao.grant(
          dao.address,
          plugin.address,
          DAO_PERMISSIONS.EXECUTE_PERMISSION_ID
        );

        // Check that the no one submited an approve yet.
        let proposal = await plugin.getProposal(id);
        expect(proposal.approvals).to.be.equal(0);

        // Approve with Alice, but without try execution..
        await plugin.connect(alice).approve(id, false);

        // Check that the `minApprovals` threshold is not met yet.
        expect(proposal.parameters.minApprovals).to.equal(
          defaultInitData.settings.minApprovals
        );
        expect(proposal.approvals).to.be.lt(
          defaultInitData.settings.minApprovals
        );
        proposal = await plugin.getProposal(id);
        expect(proposal.approvals).to.be.equal(1);

        // Revoke execute permission from ANY_ADDR
        await dao.revoke(
          plugin.address,
          ANY_ADDR,
          EXECUTE_PROPOSAL_PERMISSION_ID
        );

        // Approve with Bob and try execution.
        await plugin.connect(bob).approve(id, true);

        // Check that the `minApprovals` threshold is met.
        proposal = await plugin.getProposal(id);
        expect(proposal.approvals).to.be.equal(
          defaultInitData.settings.minApprovals
        );
        expect(await plugin.canExecute(id)).to.be.true;
        expect(proposal.approvals).to.be.equal(2);
        expect(proposal.executed).to.be.equal(false);
      });
    });
  });
});
