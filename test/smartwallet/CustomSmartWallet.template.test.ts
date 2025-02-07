import { MockContract, smock } from '@defi-wonderland/smock';
import { CustomSmartWallet, CustomSmartWallet__factory } from 'typechain-types';
import chai, { expect } from 'chai';
import chaiAsPromised from 'chai-as-promised';
import { ethers as hardhat } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

chai.use(smock.matchers);
chai.use(chaiAsPromised);

const ZERO_ADDRESS = hardhat.constants.AddressZero;

describe('CustomSmartWallet template', function () {
  describe('Function initialize()', function () {
    let customSmartWalletMock: MockContract<CustomSmartWallet>;

    beforeEach(async function () {
      const customSmartWalletFactoryMock =
        await smock.mock<CustomSmartWallet__factory>('CustomSmartWallet');

      customSmartWalletMock = await customSmartWalletFactoryMock.deploy();
    });

    it('Should be initialized during the deployment', async function () {
      expect(await customSmartWalletMock.isInitialized()).to.be.true;
    });

    it('Should fail to initialize if alredy initialized', async function () {
      const [owner] = (await hardhat.getSigners()) as [SignerWithAddress];
      await expect(
        customSmartWalletMock.initialize(
          owner.address,
          ZERO_ADDRESS,
          ZERO_ADDRESS,
          ZERO_ADDRESS,
          '0',
          '50000',
          '0x'
        )
      ).to.be.rejectedWith('already initialized');
    });
  });
});
