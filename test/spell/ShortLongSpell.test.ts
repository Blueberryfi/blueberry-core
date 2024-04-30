import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  MockBank,
  MockParaswap,
  MockParaswapTransferProxy,
  IWETH,
  WERC20,
  ShortLongSpell__factory,
  ShortLongSpell,
} from '../../typechain-types';
import { ethers, upgrades } from 'hardhat';
import { constants } from 'ethers';
import { CONTRACT_NAMES } from '../../constant';
import { fork } from '../helpers';
import chai, { expect } from 'chai';
import { near } from '../assertions/near';
import { roughlyNear } from '../assertions/roughlyNear';

chai.use(near);
chai.use(roughlyNear);

describe('ShortLongSpell', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;

  let weth: IWETH;
  let werc20: WERC20;
  let spell: ShortLongSpell;
  let bank: MockBank;
  let tokenTransferProxy: MockParaswapTransferProxy;
  let augustusSwapper: MockParaswap;

  beforeEach(async () => {
    await fork(17089048);

    [admin, alice] = await ethers.getSigners();

    const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
    werc20 = <WERC20>await upgrades.deployProxy(WERC20, [admin.address], { unsafeAllow: ['delegatecall'] });

    const MockWethFactory = await ethers.getContractFactory(CONTRACT_NAMES.MockWETH);
    weth = <IWETH>await MockWethFactory.deploy();

    const MockBankFactory = await ethers.getContractFactory(CONTRACT_NAMES.MockBank);
    bank = <MockBank>await MockBankFactory.deploy();

    const MockParaswapTransferProxyFactory = await ethers.getContractFactory(CONTRACT_NAMES.MockParaswapTransferProxy);
    tokenTransferProxy = <MockParaswapTransferProxy>await MockParaswapTransferProxyFactory.deploy();

    const MockParaswapFactory = await ethers.getContractFactory(CONTRACT_NAMES.MockParaswap);
    augustusSwapper = <MockParaswap>await MockParaswapFactory.deploy(tokenTransferProxy.address);

    const ShortLongSpellFactory = await ethers.getContractFactory(CONTRACT_NAMES.ShortLongSpell);

    spell = <ShortLongSpell>(
      await upgrades.deployProxy(
        ShortLongSpellFactory,
        [
          bank.address,
          werc20.address,
          weth.address,
          augustusSwapper.address,
          tokenTransferProxy.address,
          admin.address,
        ],
        { unsafeAllow: ['delegatecall'] }
      )
    );
  });

  describe('Constructor', () => {
    let ShortLongSpellFactory: ShortLongSpell__factory;

    beforeEach(async () => {
      ShortLongSpellFactory = await ethers.getContractFactory(CONTRACT_NAMES.ShortLongSpell);
    });

    it('should revert when bank is address(0)', async () => {
      await expect(
        upgrades.deployProxy(
          ShortLongSpellFactory,
          [
            constants.AddressZero,
            werc20.address,
            weth.address,
            augustusSwapper.address,
            tokenTransferProxy.address,
            admin.address,
          ],
          { unsafeAllow: ['delegatecall'] }
        )
      ).to.be.revertedWithCustomError(spell, 'ZERO_ADDRESS');
    });

    it('should revert when werc20 is address(0)', async () => {
      await expect(
        upgrades.deployProxy(
          ShortLongSpellFactory,
          [
            bank.address,
            constants.AddressZero,
            weth.address,
            augustusSwapper.address,
            tokenTransferProxy.address,
            admin.address,
          ],
          { unsafeAllow: ['delegatecall'] }
        )
      ).to.be.revertedWithCustomError(spell, 'ZERO_ADDRESS');
    });

    it('should revert when weth is address(0)', async () => {
      await expect(
        upgrades.deployProxy(
          ShortLongSpellFactory,
          [
            bank.address,
            werc20.address,
            constants.AddressZero,
            augustusSwapper.address,
            tokenTransferProxy.address,
            admin.address,
          ],
          { unsafeAllow: ['delegatecall'] }
        )
      ).to.be.revertedWithCustomError(spell, 'ZERO_ADDRESS');
    });

    it('should revert when augustus swapper is address(0)', async () => {
      await expect(
        upgrades.deployProxy(
          ShortLongSpellFactory,
          [
            bank.address,
            werc20.address,
            weth.address,
            constants.AddressZero,
            tokenTransferProxy.address,
            admin.address,
          ],
          { unsafeAllow: ['delegatecall'] }
        )
      ).to.be.revertedWithCustomError(spell, 'ZERO_ADDRESS');
    });

    it('should revert when token transfer proxy is address(0)', async () => {
      await expect(
        upgrades.deployProxy(
          ShortLongSpellFactory,
          [bank.address, werc20.address, weth.address, augustusSwapper.address, constants.AddressZero, admin.address],
          { unsafeAllow: ['delegatecall'] }
        )
      ).to.be.revertedWithCustomError(spell, 'ZERO_ADDRESS');
    });

    it('Check initial values', async () => {
      expect(await spell.getBank()).to.eq(bank.address);
      expect(await spell.getWrappedERC20()).to.eq(werc20.address);
      expect(await spell.getWETH()).to.eq(weth.address);
      expect(await spell.getAugustusSwapper()).to.eq(augustusSwapper.address);
      expect(await spell.getTokenTransferProxy()).to.eq(tokenTransferProxy.address);
      expect(await spell.owner()).to.eq(admin.address);
      expect(await werc20.isApprovedForAll(spell.address, bank.address)).to.be.true;
    });

    it('should revert initializing twice', async () => {
      await expect(
        spell.initialize(
          bank.address,
          werc20.address,
          weth.address,
          augustusSwapper.address,
          constants.AddressZero,
          admin.address
        )
      ).to.be.revertedWith('Initializable: contract is already initialized');
    });
  });

  describe('#addStrategy', () => {
    it('should revert when msg.sender is not admin', async () => {
      await expect(spell.connect(alice).addStrategy(weth.address, 1, 10)).to.be.revertedWith(
        'Ownable: caller is not the owner'
      );
    });

    it('should revert when vault is address(0)', async () => {
      await expect(spell.connect(admin).addStrategy(constants.AddressZero, 1, 10)).to.be.revertedWithCustomError(
        spell,
        'ZERO_ADDRESS'
      );
    });

    it('should revert when maxPosSize is 0', async () => {
      await expect(spell.connect(admin).addStrategy(weth.address, 0, 0)).to.be.revertedWithCustomError(
        spell,
        'ZERO_AMOUNT'
      );
    });

    it('should revert when minCollSize >= maxPosSize', async () => {
      await expect(spell.connect(admin).addStrategy(weth.address, 10, 10)).to.be.revertedWithCustomError(
        spell,
        'INVALID_POS_SIZE'
      );
    });

    it('should add new strategy', async () => {
      await spell.connect(admin).addStrategy(weth.address, 1, 10);

      const strategy = await spell.getStrategy(0);
      expect(strategy.vault).to.eq(weth.address);
      expect(strategy.minIsolatedCollateral).to.eq(1);
      expect(strategy.maxPositionSize).to.eq(10);
    });

    it('should emit StrategyAdded event', async () => {
      const tx = await spell.connect(admin).addStrategy(weth.address, 1, 10);

      await expect(tx).to.emit(spell, 'StrategyAdded').withArgs(0, weth.address, 1, 10);
    });
  });
});
