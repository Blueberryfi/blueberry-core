import { ethers } from 'hardhat';
import { deployBTokens } from '../helpers/money-market';
import { fork } from '../helpers';
import { ADDRESS } from '../../constant';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BErc20Delegator, Comptroller, ERC20 } from '../../typechain-types';
import { faucetToken } from '../helpers/paraswap';
import { BigNumber, utils } from 'ethers';
import { expect } from 'chai';

/* eslint-disable @typescript-eslint/no-unused-vars */
describe('Money Market', async () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let comptroller: Comptroller;

  let bWETH: BErc20Delegator;
  let bBAL: BErc20Delegator;
  let bUSDC: BErc20Delegator;
  let bWBTC: BErc20Delegator;
  let bOHM: BErc20Delegator;

  before(async () => {
    await fork(1);
    [admin, alice] = await ethers.getSigners();

    const market = await deployBTokens(admin.address);

    comptroller = market.comptroller;
    bWETH = market.bWETH;
    comptroller._setCollateralFactor(bWETH.address, utils.parseUnits('0.8', 18));
    bBAL = market.bBAL;
    comptroller._setCollateralFactor(bWETH.address, utils.parseUnits('0.8', 18));
    bUSDC = market.bUSDC;
    comptroller._setCollateralFactor(bWETH.address, utils.parseUnits('0.8', 18));
    bWBTC = market.bWBTC;
    comptroller._setCollateralFactor(bWETH.address, utils.parseUnits('0.8', 18));
    bOHM = market.bOHM;
    comptroller._setCollateralFactor(bWETH.address, utils.parseUnits('0.8', 18));

    await faucetToken(ADDRESS.WETH, utils.parseUnits('100', 18), admin);
  });

  beforeEach(async () => {
    // Transfer WETH to alice
    const weth = await ethers.getContractAt('IERC20', ADDRESS.WETH, admin);
    await weth.connect(admin).transfer(alice.address, utils.parseUnits('1', 18));

    // Lend WETH to the market
    await weth.connect(alice).approve(bWETH.address, utils.parseUnits('1', 18));
    await bWETH.connect(alice).mint(utils.parseUnits('1', 18));
    await comptroller.connect(alice).enterMarkets([bWETH.address]);
    await comptroller._setCollateralFactor(bWETH.address, utils.parseUnits('0.8', 18));
  });

  it('successfully borrow from a market | 18 decimals', async () => {
    const underlying = await ethers.getContractAt('ERC20', await bBAL.underlying(), admin);

    const amount = utils.parseUnits('10000', 18);
    await faucetToken(ADDRESS.BAL, amount, admin);
    await underlying.connect(admin).approve(bBAL.address, amount);
    await bBAL.connect(admin).mint(amount);

    // Borrow bBAL from the market
    const borrowAmount = utils.parseUnits('4', 18);
    await bBAL.connect(alice).borrow(borrowAmount);
    expect(await underlying.balanceOf(alice.address)).to.be.equal(borrowAmount);
  });

  it('fail to borrow more than your collateral value | 18 decimals', async () => {
    const underlyingAddr = await bBAL.underlying();
    const underlying = await ethers.getContractAt('ERC20', underlyingAddr, admin);

    const amount = utils.parseUnits('10000', 18);
    await faucetToken(ADDRESS.BAL, amount, admin);
    await underlying.connect(admin).approve(bBAL.address, amount);
    await bBAL.connect(admin).mint(amount);

    // Borrow bBAL from the market
    expect(await bBAL.connect(alice).borrow(utils.parseUnits('500', 18))).to.be.revertedWith(
      'revert Insufficient collateral'
    );
  });

  it('successfully borrow from a market | 9 decimals', async () => {
    const seedAmount = utils.parseUnits('500', 9);
    const underlying = await ethers.getContractAt('ERC20', await bOHM.underlying(), admin);

    await faucetToken(underlying.address, seedAmount, admin);
    await underlying.connect(admin).approve(bOHM.address, seedAmount);
    await bOHM.connect(admin).mint(seedAmount);

    // Borrow OHM from the market
    const borrowAmount = utils.parseUnits('12', 9);
    await bOHM.connect(alice).borrow(borrowAmount);
    expect(await underlying.balanceOf(alice.address)).to.be.equal(borrowAmount);
  });

  it('fail to borrow more than your collateral value | 9 decimals', async () => {
    const seedAmount = utils.parseUnits('500', 9);
    const underlying = await ethers.getContractAt('ERC20', await bOHM.underlying(), admin);

    await faucetToken(underlying.address, seedAmount, admin);
    await underlying.connect(admin).approve(bOHM.address, seedAmount);
    await bOHM.connect(admin).mint(seedAmount);

    // Borrow OHM from the market
    const borrowAmount = utils.parseUnits('20', 9);
    expect(await bOHM.connect(alice).borrow(borrowAmount)).to.be.revertedWith('revert Insufficient collateral');
  });

  it('successfully borrow from a market | 8 decimals', async () => {
    const seedAmount = utils.parseUnits('100', 8);
    const underlying = await ethers.getContractAt('ERC20', await bWBTC.underlying(), admin);

    await faucetToken(underlying.address, seedAmount, admin);
    await underlying.connect(admin).approve(bWBTC.address, seedAmount);
    await bWBTC.connect(admin).mint(seedAmount);

    // Borrow bOHM from the market
    const borrowAmount = utils.parseUnits('.001', 8);
    await bWBTC.connect(alice).borrow(borrowAmount);
    expect(await underlying.balanceOf(alice.address)).to.be.equal(borrowAmount);
  });

  it('fail to borrow more than your collateral value | 8 decimals', async () => {
    const seedAmount = utils.parseUnits('100', 8);
    const underlying = await ethers.getContractAt('ERC20', await bWBTC.underlying(), admin);

    await faucetToken(underlying.address, seedAmount, admin);
    await underlying.connect(admin).approve(bWBTC.address, seedAmount);
    await bWBTC.connect(admin).mint(seedAmount);

    // Borrow WBTC from the market
    const borrowAmount = utils.parseUnits('.01', 8);
    expect(await bWBTC.connect(alice).borrow(borrowAmount)).to.be.revertedWith('revert Insufficient collateral');
  });

  it('successfully borrow from a market | 6 decimals', async () => {
    const seedAmount = utils.parseUnits('10000', 6);
    const underlying = await ethers.getContractAt('ERC20', await bUSDC.underlying(), admin);

    await faucetToken(underlying.address, seedAmount, admin);
    await underlying.connect(admin).approve(bUSDC.address, seedAmount);
    await bUSDC.connect(admin).mint(seedAmount);

    // Borrow bOHM from the market
    const borrowAmount = utils.parseUnits('100', 6);
    await bUSDC.connect(alice).borrow(borrowAmount);
    expect(await underlying.balanceOf(alice.address)).to.be.equal(borrowAmount);
  });

  it('fail to borrow more than your collateral value | 6 decimals', async () => {
    const seedAmount = utils.parseUnits('10000', 6);
    const underlying = await ethers.getContractAt('ERC20', await bUSDC.underlying(), admin);

    await faucetToken(underlying.address, seedAmount, admin);
    await underlying.connect(admin).approve(bUSDC.address, seedAmount);
    await bUSDC.connect(admin).mint(seedAmount);

    // Borrow bOHM from the market
    const borrowAmount = utils.parseUnits('1000', 6);
    expect(await bUSDC.connect(alice).borrow(borrowAmount)).to.be.revertedWith('revert Insufficient collateral');
  });
});

async function seedMarket(bToken: BErc20Delegator, underlying: ERC20, admin: SignerWithAddress, amount: BigNumber) {
  await faucetToken(underlying.address, amount, admin);
  await underlying.connect(admin).approve(bToken.address, amount);
  await bToken.connect(admin).mint(amount);
}
