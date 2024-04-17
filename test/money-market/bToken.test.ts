import { ethers } from 'hardhat';
import chai, { expect } from 'chai';
import { near } from '../assertions/near';
import { roughlyNear } from '../assertions/roughlyNear';
import { fork } from '../helpers';
import { setupOracles } from '../spell/strategies/utils';
import { deployBTokens } from '../helpers/money-market';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BErc20Delegator, BWrappedNativeDelegator, BTokenAdmin, Comptroller } from '../../typechain-types';

chai.use(near);
chai.use(roughlyNear);

describe('BToken Money Market', () => {
  let admin: SignerWithAddress;
  let bank: SignerWithAddress;
  let softVault: SignerWithAddress;
  let comptroller: Comptroller;

  let bUSDC: BErc20Delegator;
  let bTokenAdmin: BTokenAdmin;
  let bWETH: BWrappedNativeDelegator;

  before(async () => {
    await fork();
    [admin, softVault, bank] = await ethers.getSigners();

    const oracle = await setupOracles();
    const bTokens = await deployBTokens(admin.address, oracle.address);
    bUSDC = bTokens.bUSDC;
    bWETH = bTokens.bWETH;
    comptroller = bTokens.comptroller;
    bTokenAdmin = bTokens.bTokenAdmin;
  });

  describe('Mint', () => {
    it('should revert when caller is not soft vault', async () => {
      const amount = ethers.BigNumber.from(ethers.utils.randomBytes(32));
      await expect(bUSDC.mint(amount)).to.be.revertedWith('caller should be softvault');
      await expect(bWETH.mint(amount)).to.be.revertedWith('caller should be softvault');
    });

    it('should not revert when caller is soft vault', async () => {
      const amount = ethers.BigNumber.from(ethers.utils.randomBytes(32));
      await bTokenAdmin._setSoftVault(bUSDC.address, softVault.address);
      await bTokenAdmin._setSoftVault(bWETH.address, softVault.address);

      await expect(bUSDC.connect(softVault).mint(amount)).to.not.be.revertedWith('caller should be softvault');
      await expect(bWETH.connect(softVault).mint(amount)).to.not.be.revertedWith('caller should be softvault');
    });
  });

  describe('Borrow', () => {
    it('should revert when caller is not bank', async () => {
      const amount = ethers.BigNumber.from(ethers.utils.randomBytes(32));
      await expect(bUSDC.borrow(amount)).to.be.revertedWith('only bank can borrow');
      await expect(bWETH.borrow(amount)).to.be.revertedWith('only bank can borrow');
    });

    it('should not revert when caller is bank', async () => {
      const amount = ethers.BigNumber.from(ethers.utils.randomBytes(32));
      await comptroller._setCreditLimit(bank.address, bUSDC.address, amount);
      await comptroller._setCreditLimit(bank.address, bWETH.address, amount);

      await expect(bUSDC.connect(bank).borrow(amount)).to.not.be.revertedWith('only bank can borrow');
      await expect(bWETH.connect(bank).borrow(amount)).to.not.be.revertedWith('only bank can borrow');
    });
  });
});
