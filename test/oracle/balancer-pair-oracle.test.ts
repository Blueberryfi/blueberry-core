import chai, { assert } from "chai";
import { BigNumber, utils } from "ethers";
import { ethers, upgrades } from "hardhat";
import { ADDRESS, CONTRACT_NAMES } from "../../constant";
import {
  ChainlinkAdapterOracle,
  CoreOracle,
  WeightedBPTOracle,
} from "../../typechain-types";
import { roughlyNear } from "../assertions/roughlyNear";

chai.use(roughlyNear);

const OneDay = 86400;

describe("Balancer Weighted Pool BPT Oracle", () => {
  let weightedOracle: WeightedBPTOracle;
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
        ADDRESS.CHAINLINK_ETH,
        ADDRESS.BAL,
      ],
      [OneDay, OneDay, OneDay, OneDay, OneDay]
    );

    await chainlinkAdapterOracle.setTokenRemappings(
      [ADDRESS.WETH],
      [
        ADDRESS.CHAINLINK_ETH,
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

    await coreOracle.setRoutes(
      [
        ADDRESS.USDC,
        ADDRESS.USDT,
        ADDRESS.DAI,
        ADDRESS.BAL,
        ADDRESS.WETH,
      ],
      [
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
      ]
    );
  });

  // Nested Weighted Pool with a Stable Pool inside
  it('Verify Price of a Nested Weighted Pool: 50WETH-50-3pool', async () => {
    const thirty = ethers.utils.parseEther('30');
    const fifty = ethers.utils.parseEther('50');

    const price = await weightedOracle.callStatic.getPrice(
      ADDRESS.BAL_WETH_3POOL,
    );

    assert(price.gte(thirty), 'Price is greater than 30');
    assert(price.lte(fifty), 'Price is less than 50');
  });

  it('Verify Price of a Weighted Pool: B-80BAL-20WETH', async () => {
    const ten = ethers.utils.parseEther('10');
    const fifteen = ethers.utils.parseEther('15');

    const price = await weightedOracle.callStatic.getPrice(
      ADDRESS.BAL_WETH,
    );
    
    assert(price.gte(ten), 'Price is greater than 10');
    assert(price.lte(fifteen), 'Price is less than 15');
  });
});
