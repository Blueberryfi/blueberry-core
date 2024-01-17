import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ethers, upgrades } from 'hardhat';
import chai, { expect } from 'chai';
import {
  ERC20,
  FeeManager,
  IBErc20,
  IUniswapV2Router02,
  IWETH,
  ProtocolConfig,
  SoftVault,
} from '../../typechain-types';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { BigNumber, utils } from 'ethers';
import { roughlyNear } from '../assertions/roughlyNear';
import { near } from '../assertions/near';

chai.use(roughlyNear);
chai.use(near);

const BUSDC = ADDRESS.bUSDC;
const USDC = ADDRESS.USDC;
const WETH = ADDRESS.WETH;

/* eslint-disable @typescript-eslint/no-unused-vars */
describe('SoftVault', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let usdc: ERC20;
  let weth: IWETH;
  let bUSDC: IBErc20;
  let vault: SoftVault;
  let config: ProtocolConfig;

  before(async () => {
    [admin, alice, treasury] = await ethers.getSigners();
    usdc = <ERC20>await ethers.getContractAt('ERC20', USDC, admin);
    weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);
    bUSDC = <IBErc20>await ethers.getContractAt('IBErc20', BUSDC);

    const ProtocolConfig = await ethers.getContractFactory('ProtocolConfig');
    config = <ProtocolConfig>await upgrades.deployProxy(ProtocolConfig, [treasury.address, admin.address], {
      unsafeAllow: ['delegatecall'],
    });
    config.startVaultWithdrawFee();

    const FeeManager = await ethers.getContractFactory('FeeManager');
    const feeManager = <FeeManager>await upgrades.deployProxy(FeeManager, [config.address, admin.address], {
      unsafeAllow: ['delegatecall'],
    });
    await feeManager.deployed();
    await config.setFeeManager(feeManager.address);
  });

  beforeEach(async () => {
    const SoftVault = await ethers.getContractFactory(CONTRACT_NAMES.SoftVault);

    vault = <SoftVault>await upgrades.deployProxy(
      SoftVault,
      [config.address, BUSDC, 'Interest Bearing USDC', 'ibUSDC', admin.address],
      {
        unsafeAllow: ['delegatecall'],
      }
    );

    await vault.deployed();
    // deposit 50 eth -> 50 WETH
    await weth.deposit({ value: utils.parseUnits('50') });
    await weth.approve(ADDRESS.UNI_V2_ROUTER, ethers.constants.MaxUint256);

    // swap 50 weth -> usdc
    const uniV2Router = <IUniswapV2Router02>(
      await ethers.getContractAt(CONTRACT_NAMES.IUniswapV2Router02, ADDRESS.UNI_V2_ROUTER)
    );
    await uniV2Router.swapExactTokensForTokens(
      utils.parseUnits('50'),
      0,
      [WETH, USDC],
      admin.address,
      ethers.constants.MaxUint256
    );
  });

  describe('Constructor', () => {
    it('should revert when bToken address is invalid', async () => {
      const SoftVault = await ethers.getContractFactory(CONTRACT_NAMES.SoftVault);
      await expect(
        upgrades.deployProxy(SoftVault, [
          config.address,
          ethers.constants.AddressZero,
          'Interest Bearing USDC',
          'ibUSDC',
          admin.address,
        ])
      ).to.be.revertedWithCustomError(SoftVault, 'ZERO_ADDRESS');
      await expect(
        upgrades.deployProxy(SoftVault, [
          ethers.constants.AddressZero,
          BUSDC,
          'Interest Bearing USDC',
          'ibUSDC',
          admin.address,
        ])
      ).to.be.revertedWithCustomError(SoftVault, 'ZERO_ADDRESS');
    });
    it('should set bToken along with uToken in constructor', async () => {
      expect(await vault.getUnderlyingToken()).to.be.equal(USDC);
      expect(await vault.getBToken()).to.be.equal(BUSDC);
    });
    it('should revert initializing twice', async () => {
      await expect(
        vault.initialize(config.address, ethers.constants.AddressZero, 'Interest Bearing USDC', 'ibUSDC', admin.address)
      ).to.be.revertedWith('Initializable: contract is already initialized');
    });
  });
  describe('Deposit', () => {
    const depositAmount = utils.parseUnits('100', 6);
    beforeEach(async () => {});
    it('should revert if deposit amount is zero', async () => {
      await expect(vault.deposit(0)).to.be.revertedWithCustomError(vault, 'ZERO_AMOUNT');
    });
    it('should be able to deposit underlying token on vault', async () => {
      await usdc.approve(vault.address, depositAmount);
      await expect(vault.deposit(depositAmount)).to.be.emit(vault, 'Deposited');
    });
    it('vault should hold the bTokens on deposit', async () => {
      await usdc.approve(vault.address, depositAmount);
      await vault.deposit(depositAmount);

      const exchangeRate = await bUSDC.exchangeRateStored();
      expect(await bUSDC.balanceOf(vault.address)).to.be.equal(
        depositAmount.mul(BigNumber.from(10).pow(18)).div(exchangeRate)
      );
    });
    it('vault should mint same amount of share tokens as bTokens received', async () => {
      await usdc.approve(vault.address, depositAmount);
      await vault.deposit(depositAmount);

      const cBalance = await bUSDC.balanceOf(vault.address);
      const shareBalance = await vault.balanceOf(admin.address);
      expect(cBalance).to.be.equal(shareBalance);
    });
  });

  describe('Withdraw', () => {
    const depositAmount = utils.parseUnits('100', 6);

    beforeEach(async () => {
      await usdc.approve(vault.address, depositAmount);
      await vault.deposit(depositAmount);
    });

    it('should revert if withdraw amount is zero', async () => {
      await expect(vault.withdraw(0)).to.be.revertedWithCustomError(vault, 'ZERO_AMOUNT');
    });

    it('should be able to withdraw underlying tokens from vault with rewards', async () => {
      const beforeUSDCBalance = await usdc.balanceOf(admin.address);
      const beforeTreasuryBalance = await usdc.balanceOf(treasury.address);
      const shareBalance = await vault.balanceOf(admin.address);

      await expect(vault.withdraw(shareBalance)).to.be.emit(vault, 'Withdrawn');

      expect(await vault.balanceOf(admin.address)).to.be.equal(0);
      expect(await bUSDC.balanceOf(vault.address)).to.be.equal(0);

      const afterUSDCBalance = await usdc.balanceOf(admin.address);
      const afterTreasuryBalance = await usdc.balanceOf(treasury.address);
      const feeRate = await config.getWithdrawVaultFee();
      const fee = depositAmount.mul(feeRate).div(10000);
      expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.near(fee);

      expect(afterUSDCBalance.sub(beforeUSDCBalance)).to.be.roughlyNear(depositAmount.sub(fee));
    });
  });

  describe('Utils', () => {
    it('should have same decimal as bToken', async () => {
      expect(await vault.decimals()).to.be.equal(6);
    });
  });
});
