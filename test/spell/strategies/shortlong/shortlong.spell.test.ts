import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BlueberryBank, WERC20, ERC20, ShortLongSpell, SoftVault } from '../../../../typechain-types';
import { ethers } from 'hardhat';
import { ADDRESS } from '../../../../constant';
import {
  ShortLongProtocol,
  evm_mine_blocks,
  fork,
  setupShortLongProtocol,
  revertToSnapshot,
  takeSnapshot,
} from '../../../helpers';
import SpellABI from '../../../../abi/contracts/spell/ShortLongSpell.sol/ShortLongSpell.json';

import chai, { expect } from 'chai';
import { near } from '../../../assertions/near';
import { roughlyNear } from '../../../assertions/roughlyNear';
import { BigNumber, utils, BigNumberish } from 'ethers';
import { getParaswapCalldata } from '../../../helpers/paraswap';

chai.use(near);
chai.use(roughlyNear);

const WBTC = ADDRESS.WBTC;
const LINK = ADDRESS.LINK;
const WETH = ADDRESS.WETH;
const DAI = ADDRESS.DAI;
const WstETH = ADDRESS.wstETH;

/* eslint-disable @typescript-eslint/no-unused-vars */
describe('ShortLong Spell Test test', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let dai: ERC20;
  let wbtc: ERC20;
  let weth: ERC20;
  let link: ERC20;
  let wstETH: ERC20;
  let werc20: WERC20;
  let spell: ShortLongSpell;
  let bank: BlueberryBank;
  let protocol: ShortLongProtocol;
  let daiSoftVault: SoftVault;
  let linkSoftVault: SoftVault;
  let wbtcSoftVault: SoftVault;
  let wstETHSoftVault: SoftVault;

  const iface = new ethers.utils.Interface(SpellABI);

  let snapshotId: number;

  before(async () => {
    await fork();

    [admin, alice, treasury] = await ethers.getSigners();
    dai = <ERC20>await ethers.getContractAt('ERC20', DAI);
    wbtc = <ERC20>await ethers.getContractAt('ERC20', WBTC);
    weth = <ERC20>await ethers.getContractAt('ERC20', WETH);
    link = <ERC20>await ethers.getContractAt('ERC20', LINK);
    wstETH = <ERC20>await ethers.getContractAt('ERC20', WstETH);

    protocol = await setupShortLongProtocol();
    bank = protocol.bank;
    spell = protocol.shortLongSpell;
    werc20 = protocol.werc20;
    daiSoftVault = protocol.daiSoftVault;
    linkSoftVault = protocol.linkSoftVault;
    wbtcSoftVault = protocol.wbtcSoftVault;
    wstETHSoftVault = protocol.wstETHSoftVault;

    await wbtc.approve(bank.address, ethers.constants.MaxUint256);
    await weth.approve(bank.address, ethers.constants.MaxUint256);
    await dai.approve(bank.address, ethers.constants.MaxUint256);
    await link.approve(bank.address, ethers.constants.MaxUint256);
    await wstETH.approve(bank.address, ethers.constants.MaxUint256);
  });

  it('should be able to long DAI + earn wstETH (collateral: WBTC, borrowToken: DAI)', async () => {
    snapshotId = await takeSnapshot();
    console.log('Snapshot ID:', snapshotId);
    await testFarm(4, WBTC, DAI, WstETH, utils.parseUnits('0.1', 8), utils.parseUnits('100', 18), 0, wbtc);
  });

  it('should be able to close position #1', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testClosePosition(
      positionId,
      4,
      WBTC,
      DAI,
      WstETH,
      wstETHSoftVault,
      utils.parseUnits('0.1', 8),
      utils.parseUnits('0.005', 8),
      wbtc
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to long DAI + earn wstETH (collateral: WstETH, borrowToken: DAI)', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(4, WstETH, DAI, WstETH, utils.parseUnits('1', 18), utils.parseUnits('100', 18), 0, wstETH);
  });

  it('should be able to close position #2', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testClosePosition(
      positionId,
      4,
      WstETH,
      DAI,
      WstETH,
      wstETHSoftVault,
      utils.parseUnits('1', 18),
      utils.parseUnits('0.05', 18),
      wstETH
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to long DAI + earn wstETH (collateral: WETH, borrowToken: DAI)', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(4, WETH, DAI, WstETH, utils.parseUnits('1', 18), utils.parseUnits('100', 18), 0, weth);
  });

  it('should be able to close position #3', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testClosePosition(
      positionId,
      4,
      WETH,
      DAI,
      WstETH,
      wstETHSoftVault,
      utils.parseUnits('1', 18),
      utils.parseUnits('0.05', 18),
      weth
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to long DAI + earn wstETH (collateral: DAI, borrowToken: DAI)', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(4, DAI, DAI, WstETH, utils.parseUnits('1000', 18), utils.parseUnits('100', 18), 0, dai);
  });

  it('should be able to close position #4', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testClosePosition(
      positionId,
      4,
      DAI,
      DAI,
      WstETH,
      wstETHSoftVault,
      utils.parseUnits('1000', 18),
      utils.parseUnits('10', 18),
      dai
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to long DAI + earn LINK (collateral: WBTC, borrowToken: DAI)', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(1, WBTC, DAI, LINK, utils.parseUnits('0.1', 8), utils.parseUnits('100', 18), 0, wbtc);
  });

  it('should be able to close position #5', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testClosePosition(
      positionId,
      1,
      WBTC,
      DAI,
      LINK,
      linkSoftVault,
      utils.parseUnits('0.1', 8),
      utils.parseUnits('0.005', 8),
      wbtc
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to long DAI + earn LINK (collateral: WETH, borrowToken: DAI)', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(1, WETH, DAI, LINK, utils.parseUnits('1', 18), utils.parseUnits('100', 18), 0, weth);
  });

  it('should be able to close position #6', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testClosePosition(
      positionId,
      1,
      WETH,
      DAI,
      LINK,
      linkSoftVault,
      utils.parseUnits('1', 18),
      utils.parseUnits('0.05', 18),
      weth
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to long DAI + earn LINK (collateral: DAI, borrowToken: DAI)', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(1, DAI, DAI, LINK, utils.parseUnits('1000', 18), utils.parseUnits('100', 18), 0, dai);
  });

  it('should be able to close position #7', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testClosePosition(
      positionId,
      1,
      DAI,
      DAI,
      LINK,
      linkSoftVault,
      utils.parseUnits('1000', 18),
      utils.parseUnits('10', 18),
      dai
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to short DAI + earn LINK (collateral: wstETH, borrowToken: LINK)', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(
      2,
      WstETH, // Collateral Token
      LINK, // Borrow Token
      DAI, // Swap Token
      utils.parseUnits('2', 18), // wstETH Deposit Amount
      utils.parseUnits('2', 18), // LINK Borrow Amount
      0,
      wstETH
    );
  });

  it('should be able to close position #8', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testClosePosition(
      positionId,
      2,
      WstETH, // Collateral Token
      LINK, // Borrow Token
      DAI, // Swap Token
      daiSoftVault, // Soft Vault
      utils.parseUnits('2', 18), // wstETH Deposit Amount
      utils.parseUnits('1.5', 18), // Collateral Swap Amount
      wstETH
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to short DAI + earn LINK (collateral: WBTC, borrowToken: LINK)', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(2, WBTC, LINK, DAI, utils.parseUnits('0.1', 8), utils.parseUnits('2', 18), 0, wbtc);
  });

  it('should be able to close position #9', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testClosePosition(
      positionId,
      2,
      WBTC,
      LINK,
      DAI,
      daiSoftVault,
      utils.parseUnits('0.1', 8),
      utils.parseUnits('0.005', 8),
      wbtc
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to short DAI + earn LINK (collateral: WETH, borrowToken: LINK)', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(2, WETH, LINK, DAI, utils.parseUnits('1', 18), utils.parseUnits('20', 18), 0, weth);
  });

  it('should be able to close position #10', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testClosePosition(
      positionId,
      2,
      WETH,
      LINK,
      DAI,
      daiSoftVault,
      utils.parseUnits('1', 18),
      utils.parseUnits('0.05', 18),
      weth
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to short DAI + earn LINK (collateral: DAI, borrowToken: LINK)', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(2, DAI, LINK, DAI, utils.parseUnits('1000', 18), utils.parseUnits('20', 18), 0, dai);
  });

  it('should be able to close position #11', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testClosePosition(
      positionId,
      2,
      DAI,
      LINK,
      DAI,
      daiSoftVault,
      utils.parseUnits('1000', 18),
      utils.parseUnits('20', 18),
      dai
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to long DAI + earn wBTC (collateral: WETH, borrowToken: DAI)', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(3, WETH, DAI, WBTC, utils.parseUnits('1', 18), utils.parseUnits('100', 18), 0, weth);
  });

  it('should be able to close position #12', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testClosePosition(
      positionId,
      3,
      WETH,
      DAI,
      WBTC,
      wbtcSoftVault,
      utils.parseUnits('1', 18),
      utils.parseUnits('0.05', 18),
      weth
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to long DAI + earn wBTC (collateral: WBTC, borrowToken: DAI)', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(3, WBTC, DAI, WBTC, utils.parseUnits('0.1', 8), utils.parseUnits('100', 18), 0, wbtc);
  });

  it('should be able to close position #13', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testClosePosition(
      positionId,
      3,
      WBTC,
      DAI,
      WBTC,
      wbtcSoftVault,
      utils.parseUnits('0.1', 8),
      utils.parseUnits('0.01', 8),
      wbtc
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to long DAI + earn wBTC (collateral: DAI, borrowToken: DAI)', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(3, DAI, DAI, WBTC, utils.parseUnits('1000', 18), utils.parseUnits('100', 18), 0, dai);
  });

  it('should be able to close position #14', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testClosePosition(
      positionId,
      3,
      DAI,
      DAI,
      WBTC,
      wbtcSoftVault,
      utils.parseUnits('1000', 18),
      utils.parseUnits('10', 18),
      dai
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to short DAI + earn WBTC (collateral: WETH, borrowToken: WBTC)', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(2, WETH, WBTC, DAI, utils.parseUnits('1', 18), utils.parseUnits('0.01', 8), 0, weth);
  });

  it('should be able to close position #15', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testClosePosition(
      positionId,
      2,
      WETH,
      WBTC,
      DAI,
      daiSoftVault,
      utils.parseUnits('1', 18),
      utils.parseUnits('0.1', 18),
      weth
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to short DAI + earn WBTC (collateral: WBTC, borrowToken: WBTC)', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(2, WBTC, WBTC, DAI, utils.parseUnits('0.1', 8), utils.parseUnits('0.01', 8), 0, wbtc);
  });

  it('should be able to close position #16', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testClosePosition(
      positionId,
      2,
      WBTC,
      WBTC,
      DAI,
      daiSoftVault,
      utils.parseUnits('0.1', 8),
      utils.parseUnits('0.005', 8),
      wbtc
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to short DAI + earn WBTC (collateral: DAI, borrowToken: WBTC)', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(2, DAI, WBTC, DAI, utils.parseUnits('1000', 18), utils.parseUnits('0.01', 8), 0, dai);
  });

  it('should be able to close position #17', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testClosePosition(
      positionId,
      2,
      DAI,
      WBTC,
      DAI,
      daiSoftVault,
      utils.parseUnits('1000', 18),
      utils.parseUnits('20', 18),
      dai
    );
    await revertToSnapshot(snapshotId);
  });

  async function testFarm(
    strategyId: number,
    collToken: string,
    borrowToken: string,
    swapToken: string,
    depositAmount: BigNumber,
    borrowAmount: BigNumber,
    farmingPoolId: number,
    colTokenContract: any
  ) {
    const positionId = await bank.getNextPositionId();
    const beforeTreasuryBalance = await colTokenContract.balanceOf(treasury.address);
    const swapData = await getParaswapCalldata(borrowToken, swapToken, borrowAmount, spell.address, 100);

    await bank.execute(
      0,
      spell.address,
      iface.encodeFunctionData('openPosition', [
        {
          strategyId,
          collToken,
          borrowToken: borrowToken,
          collAmount: depositAmount,
          borrowAmount: borrowAmount,
          farmingPoolId,
        },
        swapData.data,
      ])
    );

    const bankInfo = await bank.getBankInfo(DAI);
    console.log('DAI Bank Info:', bankInfo);

    const pos = await bank.getPositionInfo(positionId);
    console.log('Position Info:', pos);
    console.log('Position Value:', await bank.callStatic.getPositionValue(positionId));
    expect(pos.owner).to.be.equal(admin.address);
    expect(pos.collToken).to.be.equal(werc20.address);
    expect(pos.debtToken).to.be.equal(borrowToken);
    expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;

    const afterTreasuryBalance = await colTokenContract.balanceOf(treasury.address);
    expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.equal(depositAmount.mul(50).div(10000));
  }

  async function testClosePosition(
    positionId: BigNumber,
    strategyId: number,
    collToken: string,
    borrowToken: string,
    swapToken: string,
    softVault: SoftVault,
    depositAmount: BigNumber,
    colTokenSwapAmount: BigNumberish,
    collTokenContract: any
  ) {
    await evm_mine_blocks(10000);
    const position = await bank.getPositionInfo(positionId);

    const swapAmount = await softVault.callStatic.withdraw(position.collateralSize);

    let amountToSwap = colTokenSwapAmount;
    let colTokenSwapData = '0x';
    if (collToken === borrowToken) {
      amountToSwap = 0;
    } else if (colTokenSwapAmount !== 0) {
      colTokenSwapData = (await getParaswapCalldata(collToken, borrowToken, amountToSwap, spell.address, 100)).data;
    }

    const beforeTreasuryBalance = await collTokenContract.balanceOf(treasury.address);
    const beforeColBalance = await collTokenContract.balanceOf(admin.address);

    const swapData = await getParaswapCalldata(swapToken, borrowToken, swapAmount, spell.address, 100);

    const iface = new ethers.utils.Interface(SpellABI);
    await bank.execute(
      positionId,
      spell.address,
      iface.encodeFunctionData('closePosition', [
        {
          strategyId,
          collToken,
          borrowToken: borrowToken,
          amountRepay: ethers.constants.MaxUint256,
          amountPosRemove: ethers.constants.MaxUint256,
          amountShareWithdraw: ethers.constants.MaxUint256,
          amountOutMin: 1,
          amountToSwap,
          swapData: colTokenSwapData,
        },
        swapData.data,
      ])
    );
    const afterColBalance = await collTokenContract.balanceOf(admin.address);
    console.log('Col Token Balance Change:', afterColBalance.sub(beforeColBalance));
    const depositFee = depositAmount.mul(50).div(10000);
    const withdrawFee = depositAmount.sub(depositFee).mul(50).div(10000);
    expect(afterColBalance.sub(beforeColBalance)).to.be.gte(
      depositAmount.sub(depositFee).sub(withdrawFee).sub(colTokenSwapAmount)
    );

    const afterTreasuryBalance = await collTokenContract.balanceOf(treasury.address);
    // Plus rewards fee
    expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.gte(withdrawFee.div(2));
  }
});
