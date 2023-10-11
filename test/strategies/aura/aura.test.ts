import { ethers, network } from "hardhat";
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
} from "../../../typechain-types";
import { ADDRESS, CONTRACT_NAMES } from "../../../constant";
import { setupStrategy, strategies } from "./utils";
import { getParaswapCalldataToBuy, swapEth } from "../../helpers/paraswap";
import {
  currentTime,
  evm_increaseTime,
  evm_mine_blocks,
  fork,
  latestBlockNumber,
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
  let collateralSymbol: string;
  let borrowTokenSymbol: string;
  let depositAmount: BigNumber;
  let borrowAmount: BigNumber;

  before(async () => {
    await fork();

    [admin, alice, treasury, bob] = await ethers.getSigners();

    const strategy = await setupStrategy();
    bank = strategy.protocol.bank;
    oracle = strategy.protocol.oracle;
    spell = strategy.auraSpell;
    waura = strategy.waura;
    config = strategy.protocol.config;

    dai = <ERC20>await ethers.getContractAt("ERC20", DAI);
    aura = <ERC20>await ethers.getContractAt("ERC20", AURA);
    bal = <ERC20>await ethers.getContractAt("ERC20", BAL);
    weth = <IWETH>(
      await ethers.getContractAt(CONTRACT_NAMES.IWETH, ADDRESS.WETH)
    );
    auraBooster = strategy.auraBooster;
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

            collateralSymbol = await collateralToken.symbol();
            borrowTokenSymbol = await borrowToken.symbol();

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

            await swapEth(
              collateralToken.address,
              utils.parseEther("30"),
              alice
            );
            await collateralToken
              .connect(alice)
              .approve(bank.address, ethers.constants.MaxUint256);

            await swapEth(collateralToken.address, utils.parseEther("30"), bob);
            await collateralToken
              .connect(bob)
              .approve(bank.address, ethers.constants.MaxUint256);

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

          // // https://github.com/sherlock-audit/2023-07-blueberry-judging/issues/109
          // it("Validate keeping AURA reward after others claimed reward", async () => {
          //   const aliceDepositAmount = await getTokenAmountFromUSD(
          //     collateralToken,
          //     oracle,
          //     "3000"
          //   );
          //   const aliceBorrowAmount = await getTokenAmountFromUSD(
          //     borrowToken,
          //     oracle,
          //     "4000"
          //   );

          //   // const bobDepositAmount = await getTokenAmountFromUSD(
          //   //   collateralToken,
          //   //   oracle,
          //   //   "3000"
          //   // );
          //   // const bobBorrowAmount = await getTokenAmountFromUSD(
          //   //   borrowToken,
          //   //   oracle,
          //   //   "4000"
          //   // );

          //   const positionId = await openPosition(
          //     alice,
          //     aliceDepositAmount,
          //     aliceBorrowAmount,
          //     strategyInfo.poolId ?? "0"
          //   );
          //   // const bobPositionId = await openPosition(
          //   //   bob,
          //   //   bobDepositAmount,
          //   //   bobBorrowAmount,
          //   //   strategyInfo.poolId ?? "0"
          //   // );

          //   const t1 = await currentTime();
          //   await evm_increaseTime(86400 * 30);

          //   const t2 = await currentTime();

          //   console.log("time:", t1, t2);
          //   const position = await bank.positions(positionId);
          //   // const bobPosition = await bank.positions(bobPositionId);

          //   const totalEarned = await auraRewarder.earned(waura.address);
          //   console.log(
          //     "Wrapper Total Earned:",
          //     utils.formatUnits(totalEarned)
          //   );

          //   const pendingRewardsInfo = await waura.callStatic.pendingRewards(
          //     position.collId,
          //     position.collateralSize
          //   );

          //   // const bobPendingRewardsInfo = await waura.callStatic.pendingRewards(
          //   //   bobPosition.collId,
          //   //   bobPosition.collateralSize
          //   // );

          //   const expectedAmounts = pendingRewardsInfo.rewards.map(
          //     (reward) => 0
          //   );

          //   const swapDatas = pendingRewardsInfo.tokens.map((token, idx) => ({
          //     data: "0x",
          //   }));

          //   console.log("Alice Pending Rewards", pendingRewardsInfo);
          //   // console.log("Bob Pending Rewards", bobPendingRewardsInfo);

          //   // const rewards = await swapEth(
          //   //   borrowToken.address,
          //   //   utils.parseEther("5"),
          //   //   admin
          //   // );
          //   // await bank.connect(bob).execute(
          //   //   positionId,
          //   //   spell.address,
          //   //   spell.interface.encodeFunctionData("closePositionFarm", [
          //   //     {
          //   //       strategyId: i,
          //   //       collToken: collateralToken.address,
          //   //       borrowToken: borrowToken.address,
          //   //       amountRepay: ethers.constants.MaxUint256,
          //   //       amountPosRemove: ethers.constants.MaxUint256,
          //   //       amountShareWithdraw: ethers.constants.MaxUint256,
          //   //       amountOutMin: 1,
          //   //       amountToSwap: 0,
          //   //       swapData: "0x",
          //   //     },
          //   //     expectedAmounts,
          //   //     swapDatas.map((item) => item.data),
          //   //   ])
          //   // );

          //   const alicePendingRewardsInfo =
          //     await waura.callStatic.pendingRewards(
          //       position.collId,
          //       position.collateralSize
          //     );

          //   console.log(
          //     "Alice Pending Rewards after bob closed position",
          //     alicePendingRewardsInfo
          //   );
          // });

          // // https://github.com/sherlock-audit/2023-05-blueberry-judging/issues/29
          // it("Do not fail when new reward added after deposit", async () => {
          //   const positionId = await openPosition(
          //     alice,
          //     depositAmount,
          //     borrowAmount,
          //     strategyInfo.poolId ?? "0"
          //   );

          //   await evm_increaseTime(86400 * 30);

          //   const position = await bank.positions(positionId);

          //   const totalEarned = await auraRewarder.earned(waura.address);
          //   console.log(
          //     "Wrapper Total Earned:",
          //     utils.formatUnits(totalEarned)
          //   );

          //   const pendingRewardsInfo = await waura.callStatic.pendingRewards(
          //     position.collId,
          //     position.collateralSize
          //   );

          //   const expectedAmounts = pendingRewardsInfo.rewards.map(
          //     (reward) => 0
          //   );

          //   const swapDatas = pendingRewardsInfo.tokens.map((token, idx) => ({
          //     data: "0x",
          //   }));

          //   console.log("Pending Rewards", pendingRewardsInfo);

          //   const rewards = await swapEth(
          //     borrowToken.address,
          //     utils.parseEther("5"),
          //     admin,
          //     100
          //   );

          //   await closePosition(
          //     alice,
          //     positionId,
          //     ethers.constants.MaxUint256,
          //     ethers.constants.MaxUint256,
          //     ethers.constants.MaxUint256,
          //     1,
          //     0,
          //     "0x",
          //     expectedAmounts,
          //     swapDatas.map((item) => item.data)
          //   );
          // });

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
        });
      }
    }
  }
});
