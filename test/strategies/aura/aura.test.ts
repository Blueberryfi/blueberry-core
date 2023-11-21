import { ethers, network } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, BigNumberish, utils } from "ethers";
import {
  BlueBerryBank,
  IWETH,
  ERC20,
  WAuraPools,
  ICvxPools,
  AuraSpell,
  CoreOracle,
  IRewarder,
  ProtocolConfig,
  MockVirtualBalanceRewardPool,
  MockERC20,
} from "../../../typechain-types";
import { ADDRESS, CONTRACT_NAMES } from "../../../constant";
import { setupStrategy, strategies } from "./utils";
import { getParaswapCalldataToBuy } from "../../helpers/paraswap";
import {
  addEthToContract,
  evm_increaseTime,
  evm_mine_blocks,
  fork,
  setTokenBalance,
} from "../../helpers";
import { getTokenAmountFromUSD } from "../utils";

const AUGUSTUS_SWAPPER = ADDRESS.AUGUSTUS_SWAPPER;
const TOKEN_TRANSFER_PROXY = ADDRESS.TOKEN_TRANSFER_PROXY;
const BAL = ADDRESS.BAL;
const WETH = ADDRESS.WETH;
const USDC = ADDRESS.USDC;
const DAI = ADDRESS.DAI;
const CRV = ADDRESS.CRV;
const AURA = ADDRESS.AURA;
const POOL_ID = ADDRESS.AURA_OHM_ETH_POOL_ID;
const WPOOL_ID = ADDRESS.AURA_WETH_AURA_ID;

describe("Aura Spell Strategy test", () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let treasury: SignerWithAddress;

  let bank: BlueBerryBank;
  let oracle: CoreOracle;
  let spell: AuraSpell;
  let waura: WAuraPools;
  let dai: ERC20;
  let bal: ERC20;
  let aura: ERC20;
  let weth: IWETH;
  let auraBooster: ICvxPools;
  let auraRewarder: IRewarder;
  let config: ProtocolConfig;
  let snapshotId: any;

  let collateralToken: ERC20;
  let borrowToken: ERC20;
  let depositAmount: BigNumber;
  let borrowAmount: BigNumber;
  let rewardFeePct: BigNumber;
  let extraRewarder1: MockVirtualBalanceRewardPool;
  let extraRewarder2: MockVirtualBalanceRewardPool;
  let extraRewardToken1: MockERC20;
  let extraRewardToken2: MockERC20;

  before(async () => {
    await fork();

    [admin, alice, treasury, bob] = await ethers.getSigners();

    const strategy = await setupStrategy();
    bank = strategy.protocol.bank;
    oracle = strategy.protocol.oracle;
    spell = strategy.auraSpell;
    waura = strategy.waura;
    config = strategy.protocol.config;
    rewardFeePct = await config.rewardFee();

    dai = <ERC20>await ethers.getContractAt("ERC20", DAI);
    aura = <ERC20>await ethers.getContractAt("ERC20", AURA);
    bal = <ERC20>await ethers.getContractAt("ERC20", BAL);
    weth = <IWETH>(
      await ethers.getContractAt(CONTRACT_NAMES.IWETH, ADDRESS.WETH)
    );
    auraBooster = strategy.auraBooster;

    await addEthToContract(admin, utils.parseEther("1"), auraBooster.address);
  });

  for (let i = 0; i < strategies.length; i += 1) {
    const strategyInfo = strategies[i];
    for (let j = 0; j < strategyInfo.collateralAssets.length; j += 1) {
      for (let l = 0; l < strategyInfo.borrowAssets.length; l += 1) {
        describe(`Aura Spell Test(collateral: ${strategyInfo.collateralAssets[j]}, borrow: ${strategyInfo.borrowAssets[l]})`, () => {
          before(async () => {
            collateralToken = <ERC20>(
              await ethers.getContractAt(
                "ERC20",
                strategyInfo.collateralAssets[j]
              )
            );
            borrowToken = <ERC20>(
              await ethers.getContractAt("ERC20", strategyInfo.borrowAssets[l])
            );

            depositAmount = await getTokenAmountFromUSD(
              collateralToken,
              oracle,
              "2000"
            );
            borrowAmount = await getTokenAmountFromUSD(
              borrowToken,
              oracle,
              "3000"
            );

            const poolInfo = await auraBooster.poolInfo(
              strategyInfo.poolId ?? 0
            );

            auraRewarder = <IRewarder>(
              await ethers.getContractAt("IRewarder", poolInfo.crvRewards)
            );

            await addEthToContract(
              admin,
              utils.parseEther("1"),
              await auraRewarder.rewardManager()
            );

            const MockERC20 = await ethers.getContractFactory("MockERC20");
            extraRewardToken1 = await MockERC20.deploy("Mock", "MOCK", 18);
            extraRewardToken2 = await MockERC20.deploy("Mock", "MOCK", 18);

            const MockVirtualBalanceRewardPool =
              await ethers.getContractFactory("MockVirtualBalanceRewardPool");
            extraRewarder1 = await MockVirtualBalanceRewardPool.deploy(
              auraRewarder.address,
              extraRewardToken1.address
            );
            extraRewarder1.setRewardPerToken(utils.parseEther("1"));
            extraRewarder2 = await MockVirtualBalanceRewardPool.deploy(
              auraRewarder.address,
              extraRewardToken1.address
            );
            extraRewarder2.setRewardPerToken(utils.parseEther("1"));

            await setTokenBalance(
              collateralToken,
              alice,
              utils.parseEther("1000000")
            );
            await setTokenBalance(
              collateralToken,
              bob,
              utils.parseEther("1000000")
            );
            await collateralToken
              .connect(alice)
              .approve(bank.address, ethers.constants.MaxUint256);

            await collateralToken
              .connect(bob)
              .approve(bank.address, ethers.constants.MaxUint256);
          });

          beforeEach(async () => {
            snapshotId = await network.provider.send("evm_snapshot");
          });

          it("open position through Aura Spell", async () => {
            await openPosition(
              alice,
              depositAmount,
              borrowAmount,
              strategyInfo.poolId ?? "0"
            );

            const bankInfo = await bank.getBankInfo(borrowToken.address);
            console.log("Bank Info:", bankInfo);
          });

          it("Swap collateral to borrow token to repay debt for negative PnL", async () => {
            const positionId = await openPosition(
              alice,
              depositAmount,
              borrowAmount,
              strategyInfo.poolId ?? "0"
            );
            const position = await bank.positions(positionId);

            await evm_mine_blocks(1000);

            const pendingRewardsInfo = await waura.callStatic.pendingRewards(
              position.collId,
              position.collateralSize
            );

            const expectedAmounts = pendingRewardsInfo.rewards.map(
              (reward) => 0
            );

            const debt = await bank.callStatic.currentPositionDebt(positionId);
            const missing = debt.sub(borrowAmount);

            console.log("Missing: ", missing.toString());

            const missingDebt = await getTokenAmountFromUSD(
              borrowToken,
              oracle,
              "200"
            );

            const paraswapRes = await getParaswapCalldataToBuy(
              collateralToken.address,
              borrowToken.address,
              missingDebt.toString(),
              spell.address,
              100
            );

            const swapDatas = pendingRewardsInfo.tokens.map((token, idx) => ({
              data: "0x",
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
              swapDatas.map((item) => item.data)
            );
          });

          // https://github.com/sherlock-audit/2023-07-blueberry-judging/issues/109
          it("Validate keeping AURA reward after others claimed reward", async () => {
            // Notify big reward amount to get bigger AURA reward
            const operator = await ethers.getImpersonatedSigner(
              auraBooster.address
            );

            const rewardTokenAddr = await auraRewarder.rewardToken();

            const rewardToken = <ERC20>(
              await ethers.getContractAt("ERC20", rewardTokenAddr)
            );
            await setTokenBalance(
              rewardToken,
              auraRewarder,
              utils.parseEther("10000")
            );

            await auraRewarder
              .connect(operator)
              .queueNewRewards(utils.parseEther("10000"));

            const aliceDepositAmount = await getTokenAmountFromUSD(
              collateralToken,
              oracle,
              "3000"
            );
            const aliceBorrowAmount = await getTokenAmountFromUSD(
              borrowToken,
              oracle,
              "4000"
            );

            const bobDepositAmount = aliceDepositAmount;
            const bobBorrowAmount = aliceBorrowAmount;

            const positionId = await openPosition(
              alice,
              aliceDepositAmount,
              aliceBorrowAmount,
              strategyInfo.poolId ?? "0"
            );
            const bobPositionId = await openPosition(
              bob,
              bobDepositAmount,
              bobBorrowAmount,
              strategyInfo.poolId ?? "0"
            );

            await evm_increaseTime(8640);

            const position = await bank.positions(positionId);
            const bobPosition = await bank.positions(bobPositionId);

            const alicePendingRewardsInfoBefore =
              await waura.callStatic.pendingRewards(
                position.collId,
                position.collateralSize
              );

            const bobPendingRewardsInfoBefore =
              await waura.callStatic.pendingRewards(
                bobPosition.collId,
                bobPosition.collateralSize
              );

            const expectedAmounts = alicePendingRewardsInfoBefore.rewards.map(
              (reward) => 0
            );

            const swapDatas = alicePendingRewardsInfoBefore.tokens.map(
              (token, idx) => ({
                data: "0x",
              })
            );

            console.log("Alice Pending Rewards", alicePendingRewardsInfoBefore);
            console.log("Bob Pending Rewards", bobPendingRewardsInfoBefore);

            await setTokenBalance(borrowToken, spell, utils.parseEther("1000"));

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
              "0x",
              expectedAmounts,
              swapDatas.map((item) => item.data)
            );

            const bobPendingRewardsInfoAfter =
              await waura.callStatic.pendingRewards(
                bobPosition.collId,
                bobPosition.collateralSize
              );

            console.log(
              "Bob Pending Rewards after alice closed position",
              bobPendingRewardsInfoAfter
            );

            const aliceAuraBalanceAfter = await aura.balanceOf(alice.address);
            expect(aliceAuraBalanceAfter.sub(aliceAuraBalanceBefore)).gte(
              rewardAmountWithoutFee(alicePendingRewardsInfoBefore.rewards[1])
            );

            expect(bobPendingRewardsInfoAfter.rewards[1]).gte(
              bobPendingRewardsInfoBefore.rewards[1]
            );

            await setTokenBalance(borrowToken, spell, utils.parseEther("1000"));
            await closePosition(
              bob,
              bobPositionId,
              ethers.constants.MaxUint256,
              ethers.constants.MaxUint256,
              ethers.constants.MaxUint256,
              1,
              0,
              "0x",
              expectedAmounts,
              swapDatas.map((item) => item.data)
            );

            const bobAuraBalanceAfter = await aura.balanceOf(bob.address);
            expect(bobAuraBalanceAfter.sub(bobAuraBalanceBefore)).gte(
              rewardAmountWithoutFee(bobPendingRewardsInfoAfter.rewards[1])
            );
          });

          // https://github.com/sherlock-audit/2023-05-blueberry-judging/issues/29
          it("Do not fail when new reward added after deposit", async () => {
            // Check extra reward count, and if it's 0, add mock rewarder
            const extraRewarderLen = await auraRewarder.extraRewardsLength();
            const rewardManager = await ethers.getImpersonatedSigner(
              await auraRewarder.rewardManager()
            );
            let extraRewardAddedManually = false;

            if (extraRewarderLen.eq(0)) {
              await auraRewarder
                .connect(rewardManager)
                .addExtraReward(extraRewarder1.address);
              extraRewardAddedManually = true;
            }

            const positionId = await openPosition(
              alice,
              depositAmount,
              borrowAmount,
              strategyInfo.poolId ?? "0"
            );

            await evm_increaseTime(8640);

            if (extraRewardAddedManually) {
              await extraRewarder1.setRewardPerToken(utils.parseEther("1.5"));
            }

            const position = await bank.positions(positionId);

            const pendingRewardsInfo = await waura.callStatic.pendingRewards(
              position.collId,
              position.collateralSize
            );

            if (extraRewardAddedManually) {
              await extraRewarder1.setReward(
                waura.address,
                pendingRewardsInfo.rewards[2].add(utils.parseEther("1000"))
              );
              await setTokenBalance(
                extraRewardToken1,
                extraRewarder1,
                pendingRewardsInfo.rewards[2].add(utils.parseEther("1000"))
              );
            } else {
              extraRewardToken1 = <MockERC20>(
                await ethers.getContractAt(
                  "MockERC20",
                  pendingRewardsInfo.tokens[2]
                )
              );
            }

            await auraRewarder
              .connect(rewardManager)
              .addExtraReward(extraRewarder2.address);

            expect(await auraRewarder.extraRewardsLength()).gte(2);

            const pendingRewardsInfoAfterAdd =
              await waura.callStatic.pendingRewards(
                position.collId,
                position.collateralSize
              );
            expect(pendingRewardsInfoAfterAdd.rewards[2]).gte(
              pendingRewardsInfo.rewards[2]
            );

            const expectedAmounts = pendingRewardsInfo.rewards.map(
              (reward) => 0
            );

            const swapDatas = pendingRewardsInfo.tokens.map((token, idx) => ({
              data: "0x",
            }));

            console.log("Pending Rewards: ", pendingRewardsInfo);
            console.log(
              "Pending Rewards After new extra rewarder added: ",
              pendingRewardsInfoAfterAdd
            );

            await setTokenBalance(borrowToken, spell, utils.parseEther("1000"));

            await closePosition(
              alice,
              positionId,
              ethers.constants.MaxUint256,
              ethers.constants.MaxUint256,
              ethers.constants.MaxUint256,
              1,
              0,
              "0x",
              expectedAmounts,
              swapDatas.map((item) => item.data)
            );
          });

          // https://github.com/sherlock-audit/2023-04-blueberry-judging/issues/128
          it("Withdraw extra rewards even they were removed", async () => {
            // Check extra reward count, and if it's 0, add mock rewarder
            const extraRewarderLen = await auraRewarder.extraRewardsLength();
            const rewardManager = await ethers.getImpersonatedSigner(
              await auraRewarder.rewardManager()
            );
            let extraRewardAddedManually = false;

            if (extraRewarderLen.eq(0)) {
              await auraRewarder
                .connect(rewardManager)
                .addExtraReward(extraRewarder1.address);
              extraRewardAddedManually = true;
            }

            const positionId = await openPosition(
              alice,
              depositAmount,
              borrowAmount,
              strategyInfo.poolId ?? "0"
            );

            await evm_increaseTime(8640);

            await extraRewarder1.setRewardPerToken(utils.parseEther("2"));

            const position = await bank.positions(positionId);

            const pendingRewardsInfo = await waura.callStatic.pendingRewards(
              position.collId,
              position.collateralSize
            );

            extraRewardToken1 = <MockERC20>(
              await ethers.getContractAt(
                "MockERC20",
                pendingRewardsInfo.tokens[2]
              )
            );

            if (extraRewardAddedManually) {
              await extraRewarder1.setReward(
                waura.address,
                pendingRewardsInfo.rewards[2].add(utils.parseEther("1000"))
              );
              await setTokenBalance(
                extraRewardToken1,
                extraRewarder1,
                pendingRewardsInfo.rewards[2].add(utils.parseEther("1000"))
              );
            }

            await auraRewarder.connect(rewardManager).clearExtraRewards();
            expect(await auraRewarder.extraRewardsLength()).eq(
              BigNumber.from(0)
            );

            const pendingRewardsInfoAfterRemoval =
              await waura.callStatic.pendingRewards(
                position.collId,
                position.collateralSize
              );

            console.log("Pending Rewards: ", pendingRewardsInfo);
            expect(pendingRewardsInfo.rewards[2].gt(0)).to.be.true;
            expect(pendingRewardsInfo.rewards[2]).lte(
              pendingRewardsInfoAfterRemoval.rewards[2]
            );

            const expectedAmounts = pendingRewardsInfo.rewards.map(
              (reward) => 0
            );

            const swapDatas = pendingRewardsInfo.tokens.map((token, idx) => ({
              data: "0x",
            }));

            console.log(
              "Pending Rewards After removal: ",
              pendingRewardsInfoAfterRemoval
            );

            const rewardTokenBalanceBefore = await extraRewardToken1.balanceOf(
              alice.address
            );

            await setTokenBalance(borrowToken, spell, utils.parseEther("1000"));

            await closePosition(
              alice,
              positionId,
              ethers.constants.MaxUint256,
              ethers.constants.MaxUint256,
              ethers.constants.MaxUint256,
              1,
              0,
              "0x",
              expectedAmounts,
              swapDatas.map((item) => item.data)
            );

            const rewardTokenBalanceAfter = await extraRewardToken1.balanceOf(
              alice.address
            );

            expect(rewardTokenBalanceAfter.sub(rewardTokenBalanceBefore)).gte(
              rewardAmountWithoutFee(pendingRewardsInfo.rewards[2])
            );
          });

          afterEach(async () => {
            await network.provider.send("evm_revert", [snapshotId]);
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
              spell.interface.encodeFunctionData("openPositionFarm", [
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

            const positionId = (await bank.nextPositionId()).sub(1);

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
              spell.interface.encodeFunctionData("closePositionFarm", [
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
            return BigNumber.from(amount).sub(
              BigNumber.from(amount).mul(rewardFeePct).div(10000)
            );
          };
        });
      }
    }
  }
});