import chai from "chai";
import { utils } from "ethers";
import { ethers, upgrades } from "hardhat";
import { ADDRESS, CONTRACT_NAMES } from "../../constant";
import {
  ChainlinkAdapterOracle,
  CoreOracle,
  WeightedBPTOracle,
  StableBPTOracle,
  CompStableBPTOracle,
} from "../../typechain-types";
import { roughlyNear } from "../assertions/roughlyNear";

chai.use(roughlyNear);

const OneDay = 86400;

describe("Balancer Pair Oracle", () => {
  let weightedOracle: WeightedBPTOracle;
  let stableOracle: StableBPTOracle;
  let compStableOracle: CompStableBPTOracle;
  let coreOracle: CoreOracle;
  let chainlinkAdapterOracle: ChainlinkAdapterOracle;

  before(async () => {
    const ChainlinkAdapterOracle = await ethers.getContractFactory(
      CONTRACT_NAMES.ChainlinkAdapterOracle
    );
    chainlinkAdapterOracle = <ChainlinkAdapterOracle>(
      await ChainlinkAdapterOracle.deploy(ADDRESS.ChainlinkRegistry)
    );
    await chainlinkAdapterOracle.deployed();

    await chainlinkAdapterOracle.setTimeGap(
      [
        ADDRESS.USDC,
        ADDRESS.USDT,
        ADDRESS.DAI,
        ADDRESS.FRAX,
        ADDRESS.FRXETH,
        ADDRESS.CHAINLINK_ETH,
        ADDRESS.CHAINLINK_BTC,
        ADDRESS.BAL,
      ],
      [OneDay, OneDay, OneDay, OneDay, OneDay, OneDay, OneDay, OneDay]
    );

    await chainlinkAdapterOracle.setTokenRemappings(
      [ADDRESS.WETH, ADDRESS.FRXETH, ADDRESS.wstETH, ADDRESS.WBTC],
      [
        ADDRESS.CHAINLINK_ETH,
        ADDRESS.CHAINLINK_ETH,
        ADDRESS.CHAINLINK_ETH,
        ADDRESS.CHAINLINK_BTC,
      ]
    );

    const CoreOracle = await ethers.getContractFactory(
      CONTRACT_NAMES.CoreOracle
    );
    coreOracle = <CoreOracle>await upgrades.deployProxy(CoreOracle);

    const WeightedBPTOracleFactory = await ethers.getContractFactory(
      CONTRACT_NAMES.WeightedBPTOracle
    );
    weightedOracle = <WeightedBPTOracle>(
      await WeightedBPTOracleFactory.deploy(coreOracle.address)
    );
    await weightedOracle.deployed();

    const StableBPTOracleFactory = await ethers.getContractFactory(
      CONTRACT_NAMES.StableBPTOracle
    );
    stableOracle = <StableBPTOracle>(
      await StableBPTOracleFactory.deploy(coreOracle.address)
    );
    await stableOracle.deployed();

    const CompStableBPTOracleFactory = await ethers.getContractFactory(
      CONTRACT_NAMES.CompStableBPTOracle
    );
    compStableOracle = <CompStableBPTOracle>(
      await CompStableBPTOracleFactory.deploy(coreOracle.address)
    );
    await compStableOracle.deployed();

    await coreOracle.setRoutes(
      [
        ADDRESS.USDC,
        ADDRESS.USDT,
        ADDRESS.DAI,
        ADDRESS.FRAX,
        ADDRESS.FRXETH,
        ADDRESS.ETH,
        ADDRESS.WETH,
        ADDRESS.WBTC,
        ADDRESS.BAL,
        ADDRESS.wstETH,
      ],
      [
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
      ]
    );
  });

  describe("Price Feed", () => {
    it("Balancer USDC-DAI-USDT Composable Stable Lp Price", async () => {
      let price = await compStableOracle.callStatic.getPrice(ADDRESS.BAL_UDU);
      console.log(
        "Balancer USDC-DAI-USDT LP Price:",
        utils.formatUnits(price, 18)
      );
    });

    it("Balancer AURA Stable Lp Price", async () => {
      let price = await stableOracle.callStatic.getPrice(
        ADDRESS.BAL_WSTETH_STABLE
      );
      console.log(
        "Balancer wstETH-WETH LP Price:",
        utils.formatUnits(price, 18)
      );
    });

    it("Balancer Weighted Lp Price", async () => {
      let price0 = await weightedOracle.callStatic.getPrice(
        ADDRESS.BAL_WBTC_WETH
      );
      let price1 = await weightedOracle.callStatic.getPrice(
        ADDRESS.BAL_BAL_WETH
      );
      console.log(
        "Balancer WBTC-WETH LP Price:",
        utils.formatUnits(price0, 18)
      );
      console.log("Balancer BAL-WETH LP Price:", utils.formatUnits(price1, 18));
    });
  });
});
