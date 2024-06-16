import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BlueberryBank, MockOracle, ERC20, Erc4626ShortLongSpell } from '../../typechain-types';
import { ethers } from 'hardhat';
import { ADDRESS } from '../../constant';
import { ShortLongProtocol, evm_mine_blocks, fork, setupShortLongProtocol } from '../helpers';
import SpellABI from '../../abi/contracts/spell/Erc4626ShortLongSpell.sol/Erc4626ShortLongSpell.json';
import chai, { expect } from 'chai';
import { near } from '../assertions/near';
import { roughlyNear } from '../assertions/roughlyNear';
import { BigNumber, Contract, utils } from 'ethers';
import { getParaswapCalldata } from '../helpers/paraswap';

chai.use(near);
chai.use(roughlyNear);

const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const WBTC = ADDRESS.WBTC;

/* eslint-disable @typescript-eslint/no-unused-vars */
describe('Erc4626ShortLong Spell mainnet fork', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let treasury: SignerWithAddress;

  let weth: ERC20;
  let usdc: ERC20;

  let wApxEth: Contract;
  let mockOracle: MockOracle;
  let spell: Erc4626ShortLongSpell;
  let bank: BlueberryBank;
  let protocol: ShortLongProtocol;

  before(async () => {
    await fork(1, 20092566);

    [admin, alice, treasury] = await ethers.getSigners();
    usdc = <ERC20>await ethers.getContractAt('ERC20', USDC);
    weth = <ERC20>await ethers.getContractAt('ERC20', WETH);

    protocol = await setupShortLongProtocol();

    bank = protocol.bank;
    spell = protocol.erc4626ShortLongSpell;
    wApxEth = protocol.wapxETH;
    mockOracle = protocol.mockOracle;
  });

  const depositAmount = utils.parseUnits('1000', 6); // 1000 USDC
  const borrowAmount = utils.parseUnits('.5', 18); // 3,412 Dollars
  const iface = new ethers.utils.Interface(SpellABI);

  before(async () => {
    await weth.approve(bank.address, ethers.constants.MaxUint256);
    await usdc.approve(bank.address, ethers.constants.MaxUint256);
  });

  it('should revert when opening position exceeds max LTV', async () => {
    const swapData = await getParaswapCalldata(WETH, ADDRESS.pxETH, borrowAmount.mul(3), spell.address, 100);

    await expect(
      bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('openPosition', [
          {
            strategyId: 0,
            collToken: USDC,
            borrowToken: WETH,
            collAmount: 1,
            borrowAmount: borrowAmount.mul(3),
            farmingPoolId: 0,
          },
          swapData.data,
        ])
      )
    ).to.be.revertedWithCustomError(spell, 'EXCEED_MAX_LTV');
  });

  it('should revert when opening a position for non-existing strategy', async () => {
    await expect(
      bank.execute(
        0,
        spell.address,
        iface.encodeFunctionData('openPosition', [
          {
            strategyId: 100,
            collToken: USDC,
            borrowToken: WETH,
            collAmount: depositAmount,
            borrowAmount: borrowAmount,
            farmingPoolId: 0,
          },
          '0x00',
        ])
      )
    )
      .to.be.revertedWithCustomError(spell, 'STRATEGY_NOT_EXIST')
      .withArgs(spell.address, 100);
  });

  it('should be able to open a position', async () => {
    const positionId = await bank.getNextPositionId();
    const beforeTreasuryBalance = await usdc.balanceOf(treasury.address);
    const swapData = await getParaswapCalldata(WETH, ADDRESS.pxETH, borrowAmount, spell.address, 100);

    await bank.execute(
      0,
      spell.address,
      iface.encodeFunctionData('openPosition', [
        {
          strategyId: 0,
          collToken: USDC,
          borrowToken: WETH,
          collAmount: depositAmount,
          borrowAmount: borrowAmount,
          farmingPoolId: 0,
        },
        swapData.data,
      ])
    );

    const pos = await bank.getPositionInfo(positionId);
    expect(pos.owner).to.be.equal(admin.address);
    expect(pos.collToken).to.be.equal(wApxEth.address);
    expect(pos.debtToken).to.be.equal(WETH);
    expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;

    const afterTreasuryBalance = await usdc.balanceOf(treasury.address);
    expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.equal(depositAmount.mul(50).div(10000));
  });

  it('should be able to get position risk ratio', async () => {
    let risk = await bank.callStatic.getPositionRisk(1);
    let pv = await bank.callStatic.getPositionValue(1);
    let ov = await bank.callStatic.getDebtValue(1);
    let cv = await bank.callStatic.getIsolatedCollateralValue(1);

    await mockOracle.setPrice(
      [WBTC, USDC],
      [
        BigNumber.from(10).pow(18).mul(70000), // $1.5
        BigNumber.from(10).pow(18).mul(1), // $0.5
      ]
    );
    risk = await bank.callStatic.getPositionRisk(1);
    pv = await bank.callStatic.getPositionValue(1);
    ov = await bank.callStatic.getDebtValue(1);
    cv = await bank.callStatic.getIsolatedCollateralValue(1);
  });

  it('should fail to close position', async () => {
    await evm_mine_blocks(10000);
    const iface = new ethers.utils.Interface(SpellABI);
    const positionId = (await bank.getNextPositionId()).sub(1);
    const position = await bank.getPositionInfo(positionId);

    await mockOracle.setPrice(
      [WETH, USDC],
      [
        BigNumber.from(10).pow(18), // $1
        BigNumber.from(10).pow(18), // $1
      ]
    );

    const burnAmount = position.collateralSize.div(2);
    const swapAmount = await wApxEth.connect(bank.address).callStatic.burn(position.collId, burnAmount);
    const swapData = await getParaswapCalldata(ADDRESS.pxETH, WETH, swapAmount, spell.address, 100);

    await expect(
      bank.execute(
        positionId,
        spell.address,
        iface.encodeFunctionData('closePosition', [
          {
            strategyId: 0,
            collToken: USDC,
            borrowToken: WETH,
            amountRepay: ethers.constants.MaxUint256,
            amountPosRemove: ethers.constants.MaxUint256,
            amountShareWithdraw: ethers.constants.MaxUint256,
            amountOutMin: 1,
            amountToSwap: 0,
            swapData: '0x',
          },
          swapData.data,
        ])
      )
    )
      .to.be.revertedWithCustomError(spell, 'INCORRECT_LP')
      .withArgs(ADDRESS.pxETH);
  });

  it('should be able to close position partially', async () => {
    await evm_mine_blocks(100000);

    const iface = new ethers.utils.Interface(SpellABI);
    const positionId = (await bank.getNextPositionId()).sub(1);
    const position = await bank.getPositionInfo(positionId);
    const debtAmount = await bank.callStatic.currentPositionDebt(positionId);

    const burnAmount = position.collateralSize.div(2);

    const beforeTreasuryBalance = await weth.balanceOf(treasury.address);
    const beforeUSDCBalance = await usdc.balanceOf(admin.address);
    const beforeWETHBalance = await weth.balanceOf(admin.address);

    // await mockOracle.setPrice(
    //   [WETH, USDC],
    //   [
    //     BigNumber.from(10).pow(18), // $1
    //     BigNumber.from(10).pow(6), // $1
    //   ]
    // );

    const snapshotId = await ethers.provider.send('evm_snapshot', []);
    await ethers.provider.send('evm_mine', []);

    const swapAmount = await wApxEth.connect(bank.address).callStatic.burn(position.collId, burnAmount);

    const swapData = await getParaswapCalldata(ADDRESS.pxETH, WETH, swapAmount, spell.address, 100);

    await ethers.provider.send('evm_revert', [snapshotId]);

    await bank.execute(
      positionId,
      spell.address,
      iface.encodeFunctionData('closePosition', [
        {
          strategyId: 0,
          collToken: USDC,
          borrowToken: WETH,
          amountRepay: debtAmount.div(2),
          amountPosRemove: position.collateralSize.div(2),
          amountShareWithdraw: position.underlyingVaultShare.div(2),
          amountOutMin: 1,
          amountToSwap: 0,
          swapData: swapData.data,
        },
        swapData.data,
      ])
    );

    const afterUSDCBalance = await usdc.balanceOf(admin.address);
    const afterWETHBalance = await weth.balanceOf(admin.address);

    const depositFee = depositAmount.mul(50).div(10000);
    const withdrawFee = depositAmount.sub(depositFee).mul(50).div(10000);

    // expect(afterWETHBalance.sub(beforeWETHBalance)).to.be.gte(depositAmount.sub(depositFee).sub(withdrawFee));

    const afterTreasuryBalance = await weth.balanceOf(treasury.address);
    // Plus rewards fee
    // expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.gte(withdrawFee.div(2));
  });

  it('should be able to close position', async () => {
    await evm_mine_blocks(100000);
    const iface = new ethers.utils.Interface(SpellABI);
    const positionId = (await bank.getNextPositionId()).sub(1);
    const position = await bank.getPositionInfo(positionId);
    const debtAmount = await bank.callStatic.currentPositionDebt(positionId);

    const burnAmount = position.collateralSize; //await bank.callStatic.takeCollateral(param.amountPosRemove);

    // Manually transfer WETH rewards to spell
    // await WETH.transfer(spell.address, utils.parseUnits('3', 18));

    const beforeTreasuryBalance = await usdc.balanceOf(treasury.address);
    const beforeUSDCBalance = await usdc.balanceOf(admin.address);
    const beforeWETHBalance = await weth.balanceOf(admin.address);

    await mockOracle.setPrice(
      [WETH, USDC],
      [
        BigNumber.from(10).pow(18), // $1
        BigNumber.from(10).pow(18), // $1
      ]
    );

    const snapshotId = await ethers.provider.send('evm_snapshot', []);
    await ethers.provider.send('evm_mine', []);

    const swapAmount = await wApxEth.connect(bank.address).callStatic.burn(position.collId, burnAmount);
    const swapData = await getParaswapCalldata(ADDRESS.pxETH, WETH, swapAmount, spell.address, 100);
    await ethers.provider.send('evm_revert', [snapshotId]);

    await bank.execute(
      positionId,
      spell.address,
      iface.encodeFunctionData('closePosition', [
        {
          strategyId: 0,
          collToken: USDC,
          borrowToken: WETH,
          amountRepay: ethers.constants.MaxUint256,
          amountPosRemove: ethers.constants.MaxUint256,
          amountShareWithdraw: ethers.constants.MaxUint256,
          amountOutMin: 1,
          amountToSwap: 0,
          swapData: '0x',
        },
        swapData.data,
      ])
    );
    const afterUSDCBalance = await usdc.balanceOf(admin.address);
    const afterWETHBalance = await weth.balanceOf(admin.address);
    const depositFee = depositAmount.mul(50).div(10000);
    const withdrawFee = depositAmount.sub(depositFee).mul(50).div(10000);

    expect(afterWETHBalance.sub(beforeWETHBalance)).to.be.gte(depositAmount.sub(depositFee).sub(withdrawFee));

    const afterTreasuryBalance = await usdc.balanceOf(treasury.address);
    // Plus rewards fee
    expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.gte(withdrawFee.div(2));
  });
});
