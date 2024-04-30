import { ethers } from 'hardhat';
import chai, { expect } from 'chai';
import { near } from '../assertions/near';
import { roughlyNear } from '../assertions/roughlyNear';
import { fork, setupShortLongProtocol } from '../helpers';
import { setupOracles } from '../spell/strategies/utils';
import { deployBTokens } from '../helpers/money-market';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BErc20Delegator, BWrappedNativeDelegator, BTokenAdmin, Comptroller, ERC20 } from '../../typechain-types';

chai.use(near);
chai.use(roughlyNear);

describe('BToken Money Market', () => {
  let admin: SignerWithAddress;
  let bank: SignerWithAddress;
  let softVault: SignerWithAddress;
  let comptroller: Comptroller;

  let usdc: ERC20;
  let weth: ERC20;
  let bUSDC: BErc20Delegator;
  let bTokenAdmin: BTokenAdmin;
  let bWETH: BWrappedNativeDelegator;

  before(async () => {
    await fork();
    [admin, softVault, bank] = await ethers.getSigners();

    await setupShortLongProtocol();

    await setupOracles();
    const bTokens = await deployBTokens(admin.address);
    bUSDC = bTokens.bUSDC;
    bWETH = bTokens.bWETH;
    comptroller = bTokens.comptroller;
    bTokenAdmin = bTokens.bTokenAdmin;

    usdc = <ERC20>await ethers.getContractAt('ERC20', await bUSDC.underlying());
    weth = <ERC20>await ethers.getContractAt('ERC20', await bWETH.underlying());
    await weth.transfer(softVault.address, await weth.balanceOf(admin.address));
  });

  describe('Mint', () => {
    it('should revert when caller is not soft vault', async () => {
      const amount = ethers.BigNumber.from(ethers.utils.randomBytes(32));
      await expect(bUSDC.mint(amount)).to.be.revertedWith('caller should be softvault');
      await expect(bWETH.mint(amount)).to.be.revertedWith('caller should be softvault');
    });

    it('should not revert when caller is soft vault', async () => {
      const amount = ethers.BigNumber.from(ethers.utils.randomBytes(2));
      await bTokenAdmin._setSoftVault(bUSDC.address, softVault.address);
      await bTokenAdmin._setSoftVault(bWETH.address, softVault.address);

      await usdc.connect(softVault).approve(bUSDC.address, amount);
      let success = await bUSDC.connect(softVault).callStatic.mint(amount);
      expect(success).to.equal(0);

      await weth.connect(softVault).approve(bWETH.address, amount);
      success = await bWETH.connect(softVault).callStatic.mint(amount);
      expect(success).to.equal(0);
    });
  });

  describe('Borrow', () => {
    it('should revert when caller is not bank', async () => {
      const amount = ethers.BigNumber.from(ethers.utils.randomBytes(32));
      await expect(bUSDC.borrow(amount)).to.be.revertedWith('only bank can borrow');
      await expect(bWETH.borrow(amount)).to.be.revertedWith('only bank can borrow');
    });

    it('should not revert when caller is bank', async () => {
      let amount = ethers.BigNumber.from(ethers.utils.randomBytes(2));
      await comptroller._setCreditLimit(bank.address, bUSDC.address, amount);
      await comptroller._setCreditLimit(bank.address, bWETH.address, amount);

      amount = ethers.BigNumber.from(10);

      await usdc.connect(softVault).approve(bUSDC.address, amount);
      await bUSDC.connect(softVault).mint(amount);

      let success = await bUSDC.connect(bank).callStatic.borrow(amount.div(2));
      expect(success).to.equal(0);

      await weth.connect(softVault).approve(bWETH.address, amount);
      await bWETH.connect(softVault).mint(amount);

      success = await bWETH.connect(bank).callStatic.borrow(amount.div(2));
      expect(success).to.equal(0);
    });
  });
});
