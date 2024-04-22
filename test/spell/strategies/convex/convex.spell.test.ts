import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {
  BlueberryBank,
  IWETH,
  ERC20,
  ConvexSpell,
  WConvexBooster,
  ICvxBooster,
  IRewarder,
  ProtocolConfig,
} from '../../../../typechain-types';
import { ethers } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from '../../../../constant';
import { CvxProtocol, setupCvxProtocol, evm_mine_blocks, fork, revertToSnapshot, takeSnapshot } from '../../../helpers';
import SpellABI from '../../../../abi/contracts/spell/ConvexSpell.sol/ConvexSpell.json';
import chai, { expect } from 'chai';
import { near } from '../../../assertions/near';
import { roughlyNear } from '../../../assertions/roughlyNear';
import { BigNumber, BigNumberish, utils } from 'ethers';
import { getParaswapCalldata } from '../../../helpers/paraswap';

chai.use(near);
chai.use(roughlyNear);

const WETH = ADDRESS.WETH;
const DAI = ADDRESS.DAI;
const USDC = ADDRESS.USDC;
const CRV = ADDRESS.CRV;
const WBTC = ADDRESS.WBTC;
const WstETH = ADDRESS.wstETH;
const LINK = ADDRESS.LINK;
const MIM = ADDRESS.MIM;
const CRV_STETH = ADDRESS.CRV_STETH;
const CRV_FRXETH = ADDRESS.CRV_FRXETH;
const CRV_MIM3CRV = ADDRESS.CRV_MIM3CRV;
const CRV_CVXCRV = ADDRESS.CRV_CVXCRV_CRV;
const POOL_ID_STETH = ADDRESS.CVX_EthStEth_Id;
const POOL_ID_FRXETH = ADDRESS.CVX_FraxEth_Id;
const POOL_ID_MIM = ADDRESS.CVX_MIM_Id;
const POOL_ID_CVXCRV = ADDRESS.CVX_CvxCrv_Id;

/* eslint-disable @typescript-eslint/no-unused-vars */
describe('Convex Spells Deploy', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let treasury: SignerWithAddress;

  let dai: ERC20;
  let wbtc: ERC20;
  let wstETH: ERC20;
  let link: ERC20;
  let mim: ERC20;
  let crvStEth: ERC20;
  let crvFrxEth: ERC20;
  let crvMim3Crv: ERC20;
  let crvCvxCrv: ERC20;
  let weth: IWETH;
  let spell: ConvexSpell;
  let wconvex: WConvexBooster;
  let bank: BlueberryBank;
  let protocol: CvxProtocol;
  let cvxBooster: ICvxBooster;
  let crvRewarder1: IRewarder;
  let crvRewarder2: IRewarder;
  let crvRewarder3: IRewarder;
  let crvRewarder4: IRewarder;
  let config: ProtocolConfig;
  let balance: BigNumber;
  const iface = new ethers.utils.Interface(SpellABI);

  let snapshotId: number;

  before(async () => {
    await fork(1);

    [admin, alice, treasury] = await ethers.getSigners();

    dai = <ERC20>await ethers.getContractAt('ERC20', DAI);
    wbtc = <ERC20>await ethers.getContractAt('ERC20', WBTC);
    wstETH = <ERC20>await ethers.getContractAt('ERC20', WstETH);
    link = <ERC20>await ethers.getContractAt('ERC20', LINK);
    mim = <ERC20>await ethers.getContractAt('ERC20', MIM);
    crvStEth = <ERC20>await ethers.getContractAt('ERC20', CRV_STETH);
    crvFrxEth = <ERC20>await ethers.getContractAt('ERC20', CRV_FRXETH);
    crvMim3Crv = <ERC20>await ethers.getContractAt('ERC20', CRV_MIM3CRV);
    crvCvxCrv = <ERC20>await ethers.getContractAt('ERC20', CRV_CVXCRV);
    weth = <IWETH>await ethers.getContractAt(CONTRACT_NAMES.IWETH, WETH);

    cvxBooster = <ICvxBooster>await ethers.getContractAt('ICvxBooster', ADDRESS.CVX_BOOSTER);
    const poolInfo1 = await cvxBooster.poolInfo(POOL_ID_STETH);
    crvRewarder1 = <IRewarder>await ethers.getContractAt('IRewarder', poolInfo1.crvRewards);
    const poolInfo2 = await cvxBooster.poolInfo(POOL_ID_FRXETH);
    crvRewarder2 = <IRewarder>await ethers.getContractAt('IRewarder', poolInfo2.crvRewards);
    const poolInfo3 = await cvxBooster.poolInfo(POOL_ID_MIM);
    crvRewarder3 = <IRewarder>await ethers.getContractAt('IRewarder', poolInfo3.crvRewards);
    const poolInfo4 = await cvxBooster.poolInfo(POOL_ID_CVXCRV);
    crvRewarder4 = <IRewarder>await ethers.getContractAt('IRewarder', poolInfo4.crvRewards);

    protocol = await setupCvxProtocol();
    bank = protocol.bank;
    spell = protocol.convexSpell;
    wconvex = protocol.wconvex;
    config = protocol.config;

    await dai.approve(bank.address, ethers.constants.MaxUint256);
    await mim.approve(bank.address, ethers.constants.MaxUint256);
    await weth.approve(bank.address, ethers.constants.MaxUint256);
    await wbtc.approve(bank.address, ethers.constants.MaxUint256);
    await wstETH.approve(bank.address, ethers.constants.MaxUint256);
    await link.approve(bank.address, ethers.constants.MaxUint256);
    await crvStEth.approve(bank.address, ethers.constants.MaxUint256);
    await crvFrxEth.approve(bank.address, ethers.constants.MaxUint256);
    await crvMim3Crv.approve(bank.address, ethers.constants.MaxUint256);
    await crvCvxCrv.approve(bank.address, ethers.constants.MaxUint256);
  });

  it('should be able to farm ETH on Convex stETH/ETH pool collateral WBTC', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(
      3,
      WBTC,
      WETH,
      utils.parseUnits('0.1', 8),
      utils.parseUnits('1', 18),
      POOL_ID_STETH,
      wbtc,
      crvRewarder1
    );
  });

  it('should be able to harvest on Convex #1', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(
      positionId,
      3,
      WBTC,
      WETH,
      utils.parseUnits('0.1', 8),
      crvRewarder1,
      utils.parseUnits('0.006', 8),
      wbtc
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to farm ETH on Convex stETH/ETH pool collateral wstETH', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(
      3,
      WstETH,
      WETH,
      utils.parseUnits('1', 18),
      utils.parseUnits('0.5', 18),
      POOL_ID_STETH,
      wstETH,
      crvRewarder1
    );
  });

  it('should be able to harvest on Convex #2', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(
      positionId,
      3,
      WstETH,
      WETH,
      utils.parseUnits('1', 18),
      crvRewarder1,
      utils.parseUnits('0.1', 18),
      wstETH
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to farm ETH on Convex stETH/ETH pool collateral WETH', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(
      3,
      WETH,
      WETH,
      utils.parseUnits('1', 18),
      utils.parseUnits('0.5', 18),
      POOL_ID_STETH,
      weth,
      crvRewarder1
    );
  });

  it('should be able to harvest on Convex #3', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(
      positionId,
      3,
      WETH,
      WETH,
      utils.parseUnits('1', 18),
      crvRewarder1,
      utils.parseUnits('0.1', 18),
      weth
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to farm ETH on Convex stETH/ETH pool collateral DAI', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(
      3,
      DAI,
      WETH,
      utils.parseUnits('1000', 18),
      utils.parseUnits('1', 18),
      POOL_ID_STETH,
      dai,
      crvRewarder1
    );
  });

  it('should be able to harvest on Convex #4', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(
      positionId,
      3,
      DAI,
      WETH,
      utils.parseUnits('1000', 18),
      crvRewarder1,
      utils.parseUnits('200', 18),
      dai
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to farm ETH on Convex stETH/ETH pool collateral LINK', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(
      3,
      LINK,
      WETH,
      utils.parseUnits('500', 18),
      utils.parseUnits('0.5', 18),
      POOL_ID_STETH,
      link,
      crvRewarder1
    );
  });

  it('should be able to harvest on Convex #5', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(
      positionId,
      3,
      LINK,
      WETH,
      utils.parseUnits('500', 18),
      crvRewarder1,
      utils.parseUnits('20', 18),
      link
    );
    await revertToSnapshot(snapshotId);
  });

  it.skip('should be able to farm ETH on Convex stETH/ETH pool collateral vault LP', async () => {
    snapshotId = await takeSnapshot();
    balance = await crvStEth.balanceOf(admin.address);
    await testFarm(3, CRV_STETH, WETH, balance, utils.parseUnits('0.5', 18), POOL_ID_STETH, crvStEth, crvRewarder1);
  });

  it.skip('should be able to harvest on Convex #6', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(positionId, 3, CRV_STETH, WETH, balance, crvRewarder1, 0, crvStEth);
    await revertToSnapshot(snapshotId);
  });

  it('should be able to farm ETH on Convex frxETH/ETH pool collateral WBTC', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(
      2,
      WBTC,
      WETH,
      utils.parseUnits('0.1', 8),
      utils.parseUnits('0.2', 18),
      POOL_ID_FRXETH,
      wbtc,
      crvRewarder2
    );
  });

  it('should be able to harvest on Convex #7', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(
      positionId,
      2,
      WBTC,
      WETH,
      utils.parseUnits('0.1', 8),
      crvRewarder2,
      utils.parseUnits('0.006', 8),
      wbtc
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to farm ETH on Convex frxETH/ETH pool collateral WstETH', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(
      2,
      WstETH,
      WETH,
      utils.parseUnits('0.5', 18),
      utils.parseUnits('0.2', 18),
      POOL_ID_FRXETH,
      wstETH,
      crvRewarder2
    );
  });

  it('should be able to harvest on Convex #8', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(
      positionId,
      2,
      WstETH,
      WETH,
      utils.parseUnits('0.5', 18),
      crvRewarder2,
      utils.parseUnits('0.2', 18),
      wstETH
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to farm ETH on Convex frxETH/ETH pool collateral WETH', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(
      2,
      WETH,
      WETH,
      utils.parseUnits('0.5', 18),
      utils.parseUnits('0.2', 18),
      POOL_ID_FRXETH,
      weth,
      crvRewarder2
    );
  });

  it('should be able to harvest on Convex #9', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(
      positionId,
      2,
      WETH,
      WETH,
      utils.parseUnits('0.5', 18),
      crvRewarder2,
      utils.parseUnits('0.1', 18),
      weth
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to farm ETH on Convex frxETH/ETH pool collateral DAI', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(
      2,
      DAI,
      WETH,
      utils.parseUnits('1000', 18),
      utils.parseUnits('1', 18),
      POOL_ID_FRXETH,
      dai,
      crvRewarder2
    );
  });

  it('should be able to harvest on Convex #10', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(
      positionId,
      2,
      DAI,
      WETH,
      utils.parseUnits('1000', 18),
      crvRewarder2,
      utils.parseUnits('150', 18),
      dai
    );
    await revertToSnapshot(snapshotId);
  });

  it('should be able to farm ETH on Convex frxETH/ETH pool collateral LINK', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(
      2,
      LINK,
      WETH,
      utils.parseUnits('500', 18),
      utils.parseUnits('1', 18),
      POOL_ID_FRXETH,
      link,
      crvRewarder2
    );
  });

  it('should be able to harvest on Convex #11', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(
      positionId,
      2,
      LINK,
      WETH,
      utils.parseUnits('500', 18),
      crvRewarder2,
      utils.parseUnits('20', 18),
      link
    );
    await revertToSnapshot(snapshotId);
  });

  it.skip('should be able to farm ETH on Convex frxETH/ETH pool collateral vault LP', async () => {
    snapshotId = await takeSnapshot();
    balance = await crvFrxEth.balanceOf(admin.address);
    await testFarm(2, CRV_FRXETH, WETH, balance, utils.parseUnits('0.5', 18), POOL_ID_FRXETH, crvFrxEth, crvRewarder2);
  });

  it.skip('should be able to harvest on Convex #12', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(positionId, 2, CRV_FRXETH, WETH, balance, crvRewarder2, 0, crvFrxEth);
    await revertToSnapshot(snapshotId);
  });

  it('should be able to farm DAI on Convex MIM/3CRV pool collateral MIM', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(
      4,
      MIM,
      DAI,
      utils.parseUnits('1000', 18),
      utils.parseUnits('1000', 18),
      POOL_ID_MIM,
      mim,
      crvRewarder3
    );
  });

  it('should be able to harvest on Convex #13', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(
      positionId,
      4,
      MIM,
      DAI,
      utils.parseUnits('1000', 18),
      crvRewarder3,
      utils.parseUnits('100', 18),
      mim
    );
    await revertToSnapshot(snapshotId);
  });

  it.skip('should be able to farm DAI on Convex MIM/3CRV pool collateral vault LP', async () => {
    snapshotId = await takeSnapshot();
    balance = await crvMim3Crv.balanceOf(admin.address);
    await testFarm(
      4,
      CRV_MIM3CRV,
      DAI,
      balance.div(2),
      utils.parseUnits('1000', 18),
      POOL_ID_MIM,
      crvMim3Crv,
      crvRewarder3
    );
  });

  it.skip('should be able to harvest on Convex #14', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(positionId, 4, CRV_MIM3CRV, DAI, balance.div(2), crvRewarder3, 0, crvMim3Crv);
    await revertToSnapshot(snapshotId);
  });

  it('should be able to farm USDC on Convex MIM/3CRV pool collateral MIM', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(
      4,
      MIM,
      USDC,
      utils.parseUnits('1000', 18),
      utils.parseUnits('1000', 6),
      POOL_ID_MIM,
      mim,
      crvRewarder3
    );
  });

  it('should be able to harvest on Convex #15', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(
      positionId,
      4,
      MIM,
      USDC,
      utils.parseUnits('1000', 18),
      crvRewarder3,
      utils.parseUnits('100', 18),
      mim
    );
    await revertToSnapshot(snapshotId);
  });

  it.skip('should be able to farm USDC on Convex MIM/3CRV pool collateral vault LP', async () => {
    snapshotId = await takeSnapshot();
    balance = await crvMim3Crv.balanceOf(admin.address);
    await testFarm(4, CRV_MIM3CRV, USDC, balance, utils.parseUnits('1000', 6), POOL_ID_MIM, crvMim3Crv, crvRewarder3);
  });

  it.skip('should be able to harvest on Convex #16', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(positionId, 4, CRV_MIM3CRV, USDC, balance, crvRewarder3, 0, crvMim3Crv);
    await revertToSnapshot(snapshotId);
  });

  it.skip('should be able to farm CRV on Convex cvxCRV/CRV pool collateral WBTC', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(
      5,
      WBTC,
      CRV,
      utils.parseUnits('0.1', 8),
      utils.parseUnits('100', 18),
      POOL_ID_CVXCRV,
      wbtc,
      crvRewarder4
    );
  });

  it.skip('should be able to harvest on Convex #17', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(
      positionId,
      5,
      WBTC,
      CRV,
      utils.parseUnits('0.1', 8),
      crvRewarder4,
      utils.parseUnits('0.01', 8),
      wbtc
    );
    await revertToSnapshot(snapshotId);
  });

  it.skip('should be able to farm CRV on Convex cvxCRV/CRV pool collateral WETH', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(
      5,
      WETH,
      CRV,
      utils.parseUnits('1', 18),
      utils.parseUnits('100', 18),
      POOL_ID_CVXCRV,
      weth,
      crvRewarder4
    );
  });

  it.skip('should be able to harvest on Convex #18', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(
      positionId,
      5,
      WETH,
      CRV,
      utils.parseUnits('1', 18),
      crvRewarder4,
      utils.parseUnits('0.01', 18),
      weth
    );
    await revertToSnapshot(snapshotId);
  });

  it.skip('should be able to farm CRV on Convex cvxCRV/CRV pool collateral DAI', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(
      5,
      DAI,
      CRV,
      utils.parseUnits('1000', 18),
      utils.parseUnits('100', 18),
      POOL_ID_CVXCRV,
      dai,
      crvRewarder4
    );
  });

  it.skip('should be able to harvest on Convex #19', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(
      positionId,
      5,
      DAI,
      CRV,
      utils.parseUnits('1000', 18),
      crvRewarder4,
      utils.parseUnits('20', 18),
      dai
    );
    await revertToSnapshot(snapshotId);
  });

  it.skip('should be able to farm CRV on Convex cvxCRV/CRV pool collateral LINK', async () => {
    snapshotId = await takeSnapshot();
    await testFarm(
      5,
      LINK,
      CRV,
      utils.parseUnits('500', 18),
      utils.parseUnits('100', 18),
      POOL_ID_CVXCRV,
      link,
      crvRewarder4
    );
  });

  it.skip('should be able to harvest on Convex #20', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(
      positionId,
      5,
      LINK,
      CRV,
      utils.parseUnits('500', 18),
      crvRewarder4,
      utils.parseUnits('5', 18),
      link
    );
    await revertToSnapshot(snapshotId);
  });

  it.skip('should be able to farm CRV on Convex cvxCRV/CRV pool collateral vault LP', async () => {
    snapshotId = await takeSnapshot();
    balance = await crvCvxCrv.balanceOf(admin.address);
    await testFarm(5, CRV_CVXCRV, CRV, balance, utils.parseUnits('100', 18), POOL_ID_CVXCRV, crvCvxCrv, crvRewarder4);
  });

  it.skip('should be able to harvest on Convex #21', async () => {
    const positionId = (await bank.getNextPositionId()).sub(1);
    await testHarvest(positionId, 5, CRV_CVXCRV, CRV, balance, crvRewarder4, 0, crvCvxCrv);
  });

  async function testFarm(
    strategyId: number,
    collToken: string,
    borrowToken: string,
    depositAmount: BigNumber,
    borrowAmount: BigNumber,
    poolId: number,
    colTokenContract: any,
    crvRewarder: IRewarder
  ) {
    const positionId = await bank.getNextPositionId();
    const beforeTreasuryBalance = await colTokenContract.balanceOf(treasury.address);
    await bank.execute(
      0,
      spell.address,
      iface.encodeFunctionData('openPositionFarm', [
        {
          strategyId,
          collToken,
          borrowToken,
          collAmount: depositAmount,
          borrowAmount: borrowAmount,
          farmingPoolId: poolId,
        },
        0,
      ])
    );

    const bankInfo = await bank.getBankInfo(borrowToken);
    console.log('Bank Info:', bankInfo);

    const pos = await bank.getPositionInfo(positionId);
    console.log('Position Info:', pos);
    console.log('Position Value:', await bank.callStatic.getPositionValue(positionId));
    expect(pos.owner).to.be.equal(admin.address);
    expect(pos.collToken).to.be.equal(wconvex.address);
    expect(pos.debtToken).to.be.equal(borrowToken);
    expect(pos.collateralSize.gt(ethers.constants.Zero)).to.be.true;

    const afterTreasuryBalance = await colTokenContract.balanceOf(treasury.address);
    expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.equal(depositAmount.mul(50).div(10000));
  }

  async function testHarvest(
    positionId: BigNumber,
    strategyId: number,
    collToken: string,
    borrowToken: string,
    depositAmount: BigNumber,
    crvRewarder: IRewarder,
    swapAmount: BigNumberish,
    collTokenContract: any
  ) {
    await evm_mine_blocks(1000);

    const position = await bank.getPositionInfo(positionId);

    const totalEarned = await crvRewarder.earned(wconvex.address);
    console.log('Wrapper Total Earned:', utils.formatUnits(totalEarned));

    const pendingRewardsInfo = await wconvex.callStatic.pendingRewards(position.collId, position.collateralSize);
    console.log('Pending Rewards', pendingRewardsInfo);

    const rewardFeeRatio = await config.getRewardFee();

    const expectedAmounts = pendingRewardsInfo.rewards.map((reward) =>
      reward.mul(BigNumber.from(10000).sub(rewardFeeRatio)).div(10000)
    );

    const swapDatas = await Promise.all(
      pendingRewardsInfo.tokens.map((token, idx) => {
        if (expectedAmounts[idx].gt(0) && token.toLowerCase() !== borrowToken.toLowerCase()) {
          return getParaswapCalldata(token, borrowToken, expectedAmounts[idx], spell.address, 100);
        } else {
          return {
            data: '0x00',
          };
        }
      })
    );

    let amountToSwap = swapAmount;
    let swapData = '0x';
    if (collToken === borrowToken) {
      amountToSwap = 0;
    } else if (swapAmount !== 0) {
      swapData = (await getParaswapCalldata(collToken, borrowToken, amountToSwap, spell.address, 100)).data;
    }

    const beforeTreasuryBalance = await collTokenContract.balanceOf(treasury.address);
    const beforeETHBalance = await admin.getBalance();
    const beforeColBalance = await collTokenContract.balanceOf(admin.address);

    const iface = new ethers.utils.Interface(SpellABI);
    await bank.execute(
      positionId,
      spell.address,
      iface.encodeFunctionData('closePositionFarm', [
        {
          param: {
            strategyId,
            collToken,
            borrowToken,
            amountRepay: ethers.constants.MaxUint256,
            amountPosRemove: ethers.constants.MaxUint256,
            amountShareWithdraw: ethers.constants.MaxUint256,
            amountOutMin: 1,
            amountToSwap,
            swapData,
          },
          amounts: expectedAmounts,
          swapDatas: swapDatas.map((item) => item.data),
        },
      ])
    );
    const afterETHBalance = await admin.getBalance();
    const afterColBalance = await collTokenContract.balanceOf(admin.address);
    console.log('ETH Balance Change:', afterETHBalance.sub(beforeETHBalance));
    console.log('Collateral Balance Change:', afterColBalance.sub(beforeColBalance));
    const depositFee = depositAmount.mul(50).div(10000);
    const withdrawFee = depositAmount.sub(depositFee).mul(50).div(10000);
    expect(afterColBalance.sub(beforeColBalance)).to.be.gte(
      depositAmount.sub(depositFee).sub(withdrawFee).sub(swapAmount)
    );

    const afterTreasuryBalance = await collTokenContract.balanceOf(treasury.address);
    // Plus rewards fee
    expect(afterTreasuryBalance.sub(beforeTreasuryBalance)).to.be.gte(withdrawFee.sub(1));
  }
});
