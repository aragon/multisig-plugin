import {createDaoProxy} from '../20_integration-testing/test-helpers';
import {Operation, TargetConfig} from '../multisig-constants';
import {
  Multisig_V1_0_0__factory,
  Multisig_V1_3_0__factory,
  Multisig__factory,
  Multisig,
} from '../test-utils/typechain-versions';
import {
  deployAndUpgradeFromToCheck,
  deployAndUpgradeSelfCheck,
  getProtocolVersion,
} from '../test-utils/uups-upgradeable';
import {latestInitializerVersion} from './../multisig-constants';
import {PLUGIN_UUPS_UPGRADEABLE_PERMISSIONS} from '@aragon/osx-commons-sdk';
import {DAO} from '@aragon/osx-ethers';
import {loadFixture} from '@nomicfoundation/hardhat-network-helpers';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {expect} from 'chai';
import {ethers} from 'hardhat';

const AlreadyInitializedSignature =
  Multisig__factory.createInterface().encodeErrorResult('AlreadyInitialized');

describe('Upgrades', () => {
  it('upgrades to a new implementation', async () => {
    const {deployer, alice, dao, defaultInitData} = await loadFixture(fixture);
    const currentContractFactory = new Multisig__factory(deployer);

    await deployAndUpgradeSelfCheck(
      deployer,
      alice,
      [
        dao.address,
        defaultInitData.members,
        defaultInitData.settings,
        defaultInitData.targetConfig,
        defaultInitData.metadata,
      ],
      'initialize',
      currentContractFactory,
      PLUGIN_UUPS_UPGRADEABLE_PERMISSIONS.UPGRADE_PLUGIN_PERMISSION_ID,
      dao
    );
  });

  it('upgrades from v1.0.0 with initializeFrom', async () => {
    const {deployer, alice, dao, defaultInitData, encodeDataForUpgrade} =
      await loadFixture(fixture);
    const currentContractFactory = new Multisig__factory(deployer);
    const legacyContractFactory = new Multisig_V1_0_0__factory(deployer);

    const data = [
      deployer,
      alice,
      [dao.address, defaultInitData.members, defaultInitData.settings],
      'initialize',
      legacyContractFactory,
      currentContractFactory,
      PLUGIN_UUPS_UPGRADEABLE_PERMISSIONS.UPGRADE_PLUGIN_PERMISSION_ID,
      dao,
      'initialize',
      [
        dao.address,
        defaultInitData.members,
        defaultInitData.settings,
        defaultInitData.targetConfig,
        defaultInitData.metadata,
      ],
    ];

    // Ensure that on the `upgrade`, `initialize` can not be called.
    try {
      await deployAndUpgradeFromToCheck(
        // @ts-expect-error correct data type
        ...data
      );
      throw new Error('');
    } catch (err: any) {
      expect(err.data).to.equal(AlreadyInitializedSignature);
    }

    data[8] = 'initializeFrom';
    // @ts-expect-error types castings will work
    data[9] = [latestInitializerVersion, encodeDataForUpgrade];

    const {proxy, fromImplementation, toImplementation} =
      await deployAndUpgradeFromToCheck(
        // @ts-expect-error correct data type
        ...data
      );

    expect(toImplementation).to.not.equal(fromImplementation); // The build did change

    const fromProtocolVersion = await getProtocolVersion(
      legacyContractFactory.attach(fromImplementation)
    );
    const toProtocolVersion = await getProtocolVersion(
      currentContractFactory.attach(toImplementation)
    );

    expect(fromProtocolVersion).to.not.deep.equal(toProtocolVersion);
    expect(fromProtocolVersion).to.deep.equal([1, 0, 0]);
    expect(toProtocolVersion).to.deep.equal([1, 4, 0]);

    // expects the plugin was reinitialized
    const newMultisig = Multisig__factory.connect(proxy.address, deployer);

    expect((await newMultisig.getTargetConfig()).target).to.deep.equal(
      deployer.address
    );
    expect((await newMultisig.getTargetConfig()).operation).to.deep.equal(
      Operation.delegatecall
    );

    // `initializeFrom` was called on the upgrade, make sure
    // `initialize` can not be called.
    await expect(
      proxy.initialize(
        dao.address,
        defaultInitData.members,
        defaultInitData.settings,
        defaultInitData.targetConfig,
        defaultInitData.metadata
      )
    ).to.be.revertedWithCustomError(proxy, 'AlreadyInitialized');
  });

  it('from v1.3.0 with initializeFrom', async () => {
    const {deployer, alice, dao, defaultInitData, encodeDataForUpgrade} =
      await loadFixture(fixture);
    const currentContractFactory = new Multisig__factory(deployer);
    const legacyContractFactory = new Multisig_V1_3_0__factory(deployer);

    const data = [
      deployer,
      alice,
      [dao.address, defaultInitData.members, defaultInitData.settings],
      'initialize',
      legacyContractFactory,
      currentContractFactory,
      PLUGIN_UUPS_UPGRADEABLE_PERMISSIONS.UPGRADE_PLUGIN_PERMISSION_ID,
      dao,
      'initialize',
      [
        dao.address,
        defaultInitData.members,
        defaultInitData.settings,
        defaultInitData.targetConfig,
        defaultInitData.metadata,
      ],
    ];

    // Ensure that on the `upgrade`, `initialize` can not be called.
    try {
      await deployAndUpgradeFromToCheck(
        // @ts-expect-error correct data type
        ...data
      );
      throw new Error('');
    } catch (err: any) {
      expect(err.data).to.equal(AlreadyInitializedSignature);
    }

    data[8] = 'initializeFrom';
    // @ts-expect-error types castings will work
    data[9] = [latestInitializerVersion, encodeDataForUpgrade];

    const {proxy, fromImplementation, toImplementation} =
      await deployAndUpgradeFromToCheck(
        // @ts-expect-error correct data type
        ...data
      );

    expect(toImplementation).to.not.equal(fromImplementation); // The build did change

    const fromProtocolVersion = await getProtocolVersion(
      legacyContractFactory.attach(fromImplementation)
    );
    const toProtocolVersion = await getProtocolVersion(
      currentContractFactory.attach(toImplementation)
    );

    expect(fromProtocolVersion).to.not.deep.equal(toProtocolVersion);
    expect(fromProtocolVersion).to.deep.equal([1, 0, 0]);
    expect(toProtocolVersion).to.deep.equal([1, 4, 0]);

    // expects the plugin was reinitialized
    const newMultisig = Multisig__factory.connect(proxy.address, deployer);

    expect((await newMultisig.getTargetConfig()).target).to.deep.equal(
      deployer.address
    );
    expect((await newMultisig.getTargetConfig()).operation).to.deep.equal(
      Operation.delegatecall
    );
    // `initializeFrom` was called on the upgrade, make sure
    // `initialize` can not be called.
    await expect(
      proxy.initialize(
        dao.address,
        defaultInitData.members,
        defaultInitData.settings,
        defaultInitData.targetConfig,
        defaultInitData.metadata
      )
    ).to.be.revertedWithCustomError(proxy, 'AlreadyInitialized');
  });
});

type FixtureResult = {
  deployer: SignerWithAddress;
  alice: SignerWithAddress;
  bob: SignerWithAddress;
  carol: SignerWithAddress;
  defaultInitData: {
    members: string[];
    settings: Multisig.MultisigSettingsStruct;
    targetConfig: TargetConfig;
    metadata: string;
  };
  dao: DAO;
  encodeDataForUpgrade: string;
};

async function fixture(): Promise<FixtureResult> {
  const [deployer, alice, bob, carol] = await ethers.getSigners();

  const dummyMetadata = '0x12345678';

  const dao = await createDaoProxy(deployer, dummyMetadata);

  // Create an initialized plugin clone
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
    metadata: '0x',
  };

  const encodeDataForUpgrade = ethers.utils.defaultAbiCoder.encode(
    ['address', 'uint8', 'bytes'],
    [deployer.address, Operation.delegatecall, '0x']
  );

  return {
    deployer,
    alice,
    bob,
    carol,
    dao,
    defaultInitData,
    encodeDataForUpgrade,
  };
}
