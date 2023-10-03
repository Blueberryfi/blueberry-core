import { ethers, network } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, utils } from "ethers";
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
import { getParaswapCalldata, swapEth } from "../../helpers/paraswap";
import { evm_mine_blocks, fork } from "../../helpers";
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

    [admin, alice, treasury] = await ethers.getSigners();

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
            snapshotId = await network.provider.send("evm_snapshot");

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
              utils.parseEther("3"),
              alice
            );
            await dai
              .connect(alice)
              .approve(bank.address, ethers.constants.MaxUint256);
          });

          it("open position through Aura Spell", async () => {
            await bank.connect(alice).execute(
              0,
              spell.address,
              spell.interface.encodeFunctionData("openPositionFarm", [
                {
                  strategyId: i,
                  collToken: collateralToken.address,
                  borrowToken: borrowToken.address,
                  collAmount: depositAmount,
                  borrowAmount: borrowAmount,
                  farmingPoolId: strategyInfo.poolId ?? "0",
                },
                1,
              ])
            );

            const bankInfo = await bank.getBankInfo(borrowToken.address);
            console.log("Bank Info:", bankInfo);
          });

          it("should be able to close portion of position without withdrawing isolated collaterals", async () => {
            await evm_mine_blocks(10000);
            const positionId = (await bank.nextPositionId()).sub(1);
            const position = await bank.positions(positionId);

            const totalEarned = await auraRewarder.earned(waura.address);
            console.log(
              "Wrapper Total Earned:",
              utils.formatUnits(totalEarned)
            );

            const pendingRewardsInfo = await waura.callStatic.pendingRewards(
              position.collId,
              position.collateralSize
            );

            const rewardFeeRatio = await config.rewardFee();

            const expectedAmounts = pendingRewardsInfo.rewards.map((reward) =>
              reward.sub(reward.mul(rewardFeeRatio).div(10000))
            );

            const swapDatas = await Promise.all(
              pendingRewardsInfo.tokens.map((token, idx) => {
                if (expectedAmounts[idx].gt(0)) {
                  return getParaswapCalldata(
                    token,
                    collateralToken.address,
                    expectedAmounts[idx],
                    spell.address,
                    100
                  );
                } else {
                  return {
                    data: "0x00",
                  };
                }
              })
            );

            console.log("Pending Rewards", pendingRewardsInfo);

            const amount = await swapEth(
              borrowToken.address,
              utils.parseEther("1"),
              admin
            );
            await borrowToken.transfer(spell.address, amount);

            await bank.connect(alice).execute(
              positionId,
              spell.address,
              spell.interface.encodeFunctionData("closePositionFarm", [
                {
                  strategyId: i,
                  collToken: collateralToken.address,
                  borrowToken: borrowToken.address,
                  amountRepay: ethers.constants.MaxUint256,
                  amountPosRemove: ethers.constants.MaxUint256,
                  amountShareWithdraw: ethers.constants.MaxUint256,
                  amountOutMin: 1,
                },
                expectedAmounts,
                swapDatas.map((item) => item.data),
              ])
            );
          });

          after(async () => {
            await network.provider.send("evm_revert", [snapshotId]);
          });
        });
      }
    }
  }
});
