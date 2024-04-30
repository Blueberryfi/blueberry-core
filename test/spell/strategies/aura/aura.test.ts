import { ethers, network } from 'hardhat';
import { expect } from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, BigNumberish, utils } from 'ethers';
import {
  BlueberryBank,
  ERC20,
  WAuraBooster,
  IAuraBooster,
  AuraSpell,
  CoreOracle,
  IRewarder,
  ICvxExtraRewarder,
  ProtocolConfig,
  IStashToken,
  MockVirtualBalanceRewardPool,
} from '../../../../typechain-types';
import { ADDRESS } from '../../../../constant';
import { setupStrategy, strategies } from './utils';
import { getParaswapCalldataToBuy } from '../../../helpers/paraswap';
import { addEthToContract, evm_mine_blocks, fork, setTokenBalance } from '../../../helpers';
import { getTokenAmountFromUSD } from '../utils';

const DAI = ADDRESS.DAI;
const AURA = ADDRESS.AURA;

/* eslint-disable @typescript-eslint/no-unused-vars */
describe('Aura Spell Strategy test', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;

  let bank: BlueberryBank;
  let oracle: CoreOracle;
  let spell: AuraSpell;
  let waura: WAuraBooster;
  let dai: ERC20;
  let aura: ERC20;
  let auraBooster: IAuraBooster;
  let auraRewarder: IRewarder;
  let config: ProtocolConfig;
  let snapshotId: any;

  let collateralToken: ERC20;
  let borrowToken: ERC20;
  let depositAmount: BigNumber;
  let borrowAmount: BigNumber;
  let rewardFeePct: BigNumber;
  let extraRewarder1: ICvxExtraRewarder;
  let extraRewarder2: MockVirtualBalanceRewardPool;
  let stashToken: IStashToken;

  before(async () => {
    await fork();

    [admin, alice, bob] = await ethers.getSigners();

    const strat = await setupStrategy();
    bank = strat.protocol.bank;
    oracle = strat.protocol.oracle;
    spell = strat.auraSpell;
    waura = strat.waura;
    config = strat.protocol.config;
    auraBooster = strat.auraBooster;
    rewardFeePct = await config.getRewardFee();

    dai = <ERC20>await ethers.getContractAt('ERC20', DAI);
    aura = <ERC20>await ethers.getContractAt('ERC20', AURA);

    await addEthToContract(admin, utils.parseEther('1'), auraBooster.address);
  });

  for (let i = 0; i < strategies.length; i += 1) {
    const strategyInfo = strategies[i];
    for (let j = 0; j < strategyInfo.collateralAssets.length; j += 1) {
      for (let l = 0; l < strategyInfo.borrowAssets.length; l += 1) {
        describe(`Aura Spell Test(collateral: ${strategyInfo.collateralAssets[j]}, borrow: ${strategyInfo.borrowAssets[l]})`, () => {
          before(async () => {
            collateralToken = <ERC20>await ethers.getContractAt('ERC20', strategyInfo.collateralAssets[j]);
            borrowToken = <ERC20>await ethers.getContractAt('ERC20', strategyInfo.borrowAssets[l]);
            depositAmount = await getTokenAmountFromUSD(collateralToken, oracle, '10000');
            borrowAmount = await getTokenAmountFromUSD(borrowToken, oracle, '10000');
            const poolInfo = await auraBooster.poolInfo(strategyInfo.poolId ?? 0);

            auraRewarder = <IRewarder>await ethers.getContractAt('IRewarder', poolInfo.crvRewards);

            await addEthToContract(admin, utils.parseEther('1'), await auraRewarder.rewardManager());

            extraRewarder1 = <ICvxExtraRewarder>(
              await ethers.getContractAt('ICvxExtraRewarder', await auraRewarder.extraRewards(0))
            );

            stashToken = <IStashToken>await ethers.getContractAt('IStashToken', await extraRewarder1.rewardToken());

            await setTokenBalance(collateralToken, alice, utils.parseEther('1000000000000'));
            await setTokenBalance(collateralToken, bob, utils.parseEther('1000000000000'));
            await collateralToken.connect(alice).approve(bank.address, ethers.constants.MaxUint256);

            await collateralToken.connect(bob).approve(bank.address, ethers.constants.MaxUint256);
          });

          beforeEach(async () => {
            snapshotId = await network.provider.send('evm_snapshot');
          });

          it('open position through Aura Spell', async () => {
            await openPosition(alice, depositAmount, borrowAmount, strategyInfo.poolId ?? '0');

            const bankInfo = await bank.getBankInfo(borrowToken.address);
          });

          it('Swap collateral to borrow token to repay debt for negative PnL', async () => {
            const positionId = await openPosition(alice, depositAmount, borrowAmount, strategyInfo.poolId ?? '0');
            const position = await bank.getPositionInfo(positionId);

            await evm_mine_blocks(1000);

            const pendingRewardsInfo = await waura.callStatic.pendingRewards(position.collId, position.collateralSize);

            const expectedAmounts = pendingRewardsInfo.rewards.map((reward: any) => reward);

            const debt = await bank.callStatic.currentPositionDebt(positionId);
            const missing = debt.sub(borrowAmount);

            const missingDebt = await getTokenAmountFromUSD(borrowToken, oracle, '200');

            const paraswapRes = await getParaswapCalldataToBuy(
              collateralToken.address,
              borrowToken.address,
              missingDebt.toString(),
              spell.address,
              100
            );

            const swapDatas = pendingRewardsInfo.tokens.map((token: any, i: any) => ({
              data: '0x',
            }));

            await closePosition(
              alice,
              positionId,
              ethers.constants.MaxUint256,
              ethers.constants.MaxUint256,
              ethers.constants.MaxUint256,
              1,
              BigNumber.from(2).mul(paraswapRes.srcAmount),
              paraswapRes.calldata.data,
              expectedAmounts,
              swapDatas.map((item: { data: any }) => item.data)
            );
          });

          it('Validate keeping AURA reward after others claimed reward', async () => {
            const aliceDepositAmount = await getTokenAmountFromUSD(collateralToken, oracle, '3000');
            const aliceBorrowAmount = await getTokenAmountFromUSD(borrowToken, oracle, '4000');

            const bobDepositAmount = aliceDepositAmount;
            const bobBorrowAmount = aliceBorrowAmount;

            const positionId = await openPosition(
              alice,
              aliceDepositAmount,
              aliceBorrowAmount,
              strategyInfo.poolId ?? '0'
            );
            const bobPositionId = await openPosition(
              bob,
              bobDepositAmount,
              bobBorrowAmount,
              strategyInfo.poolId ?? '0'
            );

            await evm_mine_blocks(10);

            const position = await bank.getPositionInfo(positionId);
            const bobPosition = await bank.getPositionInfo(bobPositionId);

            const alicePendingRewardsInfoBefore = await waura.callStatic.pendingRewards(
              position.collId,
              position.collateralSize
            );
            const bobPendingRewardsInfoBefore = await waura.callStatic.pendingRewards(
              bobPosition.collId,
              bobPosition.collateralSize
            );

            const expectedAmounts = alicePendingRewardsInfoBefore.rewards.map((reward: any) => reward);

            const swapDatas = alicePendingRewardsInfoBefore.tokens.map((token: any, i: any) => ({
              data: '0x',
            }));

            const bobSwapDatas = bobPendingRewardsInfoBefore.tokens.map((token: any, i: any) => ({
              data: '0x',
            }));

            await setTokenBalance(borrowToken, spell, utils.parseEther('1000'));

            const aliceAuraBalanceBefore = await aura.balanceOf(alice.address);
            const bobAuraBalanceBefore = await aura.balanceOf(bob.address);

            await closePosition(
              alice,
              positionId,
              ethers.constants.MaxUint256,
              ethers.constants.MaxUint256,
              ethers.constants.MaxUint256,
              1,
              0,
              '0x',
              expectedAmounts,
              swapDatas.map((item: { data: any }) => item.data)
            );

            evm_mine_blocks(1);

            const bobPendingRewardsInfoAfter = await waura.pendingRewards(
              bobPosition.collId,
              bobPosition.collateralSize
            );

            const aliceAuraBalanceAfter = await aura.balanceOf(alice.address);
            expect(aliceAuraBalanceAfter.sub(aliceAuraBalanceBefore)).gte(
              rewardAmountWithoutFee(alicePendingRewardsInfoBefore.rewards[1])
            );

            expect(bobPendingRewardsInfoAfter.rewards[1]).gte(bobPendingRewardsInfoBefore.rewards[1]);

            await setTokenBalance(borrowToken, spell, utils.parseEther('1000'));

            const bobExpectedAmounts = bobPendingRewardsInfoAfter.rewards.map((reward: any) => reward);

            await closePosition(
              bob,
              bobPositionId,
              ethers.constants.MaxUint256,
              ethers.constants.MaxUint256,
              ethers.constants.MaxUint256,
              1,
              0,
              '0x',
              bobExpectedAmounts,
              bobSwapDatas.map((item: { data: any }) => item.data)
            );

            const bobAuraBalanceAfter = await aura.balanceOf(bob.address);
            expect(bobAuraBalanceAfter.sub(bobAuraBalanceBefore)).gte(
              rewardAmountWithoutFee(bobPendingRewardsInfoAfter.rewards[1])
            );
          });

          it('Do not fail when new reward added after deposit', async () => {
            // Check extra reward count, and if it's 0, add mock rewarder
            const extraRewarderLen = await auraRewarder.extraRewardsLength();

            const rewardManager = await ethers.getImpersonatedSigner(await auraRewarder.rewardManager());
            let extraRewardAddedManually = false;

            if (extraRewarderLen.eq(0)) {
              await auraRewarder.connect(rewardManager).addExtraReward(extraRewarder1.address);
              extraRewardAddedManually = true;
            }
            const positionId = await openPosition(alice, depositAmount, borrowAmount, strategyInfo.poolId ?? '0');
            await evm_mine_blocks(10);

            const position = await bank.getPositionInfo(positionId);

            const pendingRewardsInfo = await waura.callStatic.pendingRewards(position.collId, position.collateralSize);

            const rewarderFactory = await ethers.getContractFactory('MockVirtualBalanceRewardPool');

            extraRewarder2 = <MockVirtualBalanceRewardPool>(
              await rewarderFactory.deploy(auraRewarder.address, dai.address)
            );

            await auraRewarder.connect(rewardManager).addExtraReward(extraRewarder2.address);

            const pid = BigNumber.from(strategyInfo.poolId);

            const extraRewardLength = await waura.extraRewardsLength(pid);
            await waura.syncExtraRewards(pid, position.collId);

            expect(await waura.extraRewardsLength(pid)).greaterThan(extraRewardLength);

            const pendingRewardsInfoAfterAdd = await waura.pendingRewards(position.collId, position.collateralSize);

            const expectedAmounts = pendingRewardsInfoAfterAdd.rewards.map((reward: BigNumber) => reward);

            const swapDatas = pendingRewardsInfoAfterAdd.tokens.map((token: any, i: any) => ({
              data: '0x',
            }));

            await setTokenBalance(borrowToken, spell, utils.parseEther('1000'));

            await closePosition(
              alice,
              positionId,
              ethers.constants.MaxUint256,
              ethers.constants.MaxUint256,
              ethers.constants.MaxUint256,
              1,
              0,
              '0x',
              expectedAmounts,
              swapDatas.map((item: { data: any }) => item.data)
            );
          });

          it('Withdraw extra rewards even they were removed', async () => {
            const rewardManager = await ethers.getImpersonatedSigner(await auraRewarder.rewardManager());

            const pid = BigNumber.from(strategyInfo.poolId);

            const positionId = await openPosition(alice, depositAmount, borrowAmount, pid);

            const position = await bank.getPositionInfo(positionId);

            // Open a position to update the rewarder
            await openPosition(bob, depositAmount, borrowAmount, pid);

            const pendingRewardsInfo = await waura.callStatic.pendingRewards(position.collId, position.collateralSize);

            await auraRewarder.connect(rewardManager).clearExtraRewards();

            await evm_mine_blocks(10);

            expect(await auraRewarder.extraRewardsLength()).eq(BigNumber.from(0));

            const pendingRewardsInfoAfterRemoval = await waura.callStatic.pendingRewards(
              position.collId,
              position.collateralSize
            );

            // We are comparing rewards[1] because the reward removed was stash Aura reward
            //     which is paid in Aura
            expect(pendingRewardsInfo.rewards[1].gt(0)).to.be.true;
            expect(pendingRewardsInfo.rewards[1]).lte(pendingRewardsInfoAfterRemoval.rewards[1]);

            const expectedAmounts = pendingRewardsInfo.rewards.map((reward: any) => 0);

            const swapDatas = pendingRewardsInfo.tokens.map((token: any, i: any) => ({
              data: '0x',
            }));

            const auraInstance = <ERC20>await ethers.getContractAt('ERC20', ADDRESS.AURA);

            const rewardTokenBalanceBefore = await auraInstance.balanceOf(alice.address);

            await setTokenBalance(borrowToken, spell, utils.parseEther('1000'));
            await closePosition(
              alice,
              positionId,
              ethers.constants.MaxUint256,
              ethers.constants.MaxUint256,
              ethers.constants.MaxUint256,
              1,
              0,
              '0x',
              expectedAmounts,
              swapDatas.map((item: { data: any }) => item.data)
            );

            const rewardTokenBalanceAfter = await auraInstance.balanceOf(alice.address);
            expect(rewardTokenBalanceAfter.sub(rewardTokenBalanceBefore)).gte(
              rewardAmountWithoutFee(pendingRewardsInfo.rewards[1])
            );
          });

          afterEach(async () => {
            await network.provider.send('evm_revert', [snapshotId]);
          });

          const openPosition = async (
            _account: SignerWithAddress,
            _depositAmount: BigNumberish,
            _borrowAmount: BigNumberish,
            _poolId: BigNumberish
          ): Promise<BigNumber> => {
            await bank.connect(_account).execute(
              0,
              spell.address,
              spell.interface.encodeFunctionData('openPositionFarm', [
                {
                  strategyId: i,
                  collToken: collateralToken.address,
                  borrowToken: borrowToken.address,
                  collAmount: _depositAmount,
                  borrowAmount: _borrowAmount,
                  farmingPoolId: _poolId,
                },
                1,
              ])
            );

            const positionId = (await bank.getNextPositionId()).sub(1);

            return positionId;
          };

          const closePosition = async (
            account: SignerWithAddress,
            positionId: BigNumberish,
            amountRepay: BigNumberish,
            amountPosRemove: BigNumberish,
            amountShareWithdraw: BigNumberish,
            amountOutMin: BigNumberish,
            amountToSwap: BigNumberish,
            swapData: string,
            expectedAmounts: BigNumberish[],
            swapDatas: string[]
          ) => {
            await bank.connect(account).execute(
              positionId,
              spell.address,
              spell.interface.encodeFunctionData('closePositionFarm', [
                {
                  strategyId: i,
                  collToken: collateralToken.address,
                  borrowToken: borrowToken.address,
                  amountRepay,
                  amountPosRemove,
                  amountShareWithdraw,
                  amountOutMin,
                  amountToSwap,
                  swapData,
                },
                expectedAmounts,
                swapDatas,
              ])
            );
          };

          const rewardAmountWithoutFee = (amount: BigNumberish): BigNumber => {
            return BigNumber.from(amount).sub(BigNumber.from(amount).mul(rewardFeePct).div(10000));
          };
        });
      }
    }
  }
});
