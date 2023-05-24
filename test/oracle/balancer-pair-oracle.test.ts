import chai from 'chai';
import { utils } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from "../../constant"
import {
  ChainlinkAdapterOracle,
  CoreOracle,
  BalancerPairOracle,
} from '../../typechain-types';
import { roughlyNear } from '../assertions/roughlyNear'
import { solidity } from 'ethereum-waffle'

chai.use(solidity)
chai.use(roughlyNear)

const OneDay = 86400;

describe('Balancer Pair Oracle', () => {
  let oracle: BalancerPairOracle;
  let coreOracle: CoreOracle;
  let chainlinkAdapterOracle: ChainlinkAdapterOracle;

  before(async () => {
    const ChainlinkAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracle);
    chainlinkAdapterOracle = <ChainlinkAdapterOracle>await ChainlinkAdapterOracle.deploy(ADDRESS.ChainlinkRegistry);
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
        ADDRESS.BAL
      ],
      [OneDay, OneDay, OneDay, OneDay, OneDay, OneDay, OneDay, OneDay]
    );

    await chainlinkAdapterOracle.setTokenRemappings(
      [
        ADDRESS.WETH,
        ADDRESS.FRXETH,
        ADDRESS.WBTC,
      ],
      [
        ADDRESS.CHAINLINK_ETH,
        ADDRESS.CHAINLINK_ETH,
        ADDRESS.CHAINLINK_BTC
      ]
    )

    const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
    coreOracle = <CoreOracle>await upgrades.deployProxy(CoreOracle);

    const BalancerPairOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.BalancerPairOracle);
    oracle = <BalancerPairOracle>await BalancerPairOracleFactory.deploy(
      coreOracle.address,
    );
    await oracle.deployed();

    await coreOracle.setRoutes(
      [
        ADDRESS.USDC,
        ADDRESS.USDT,
        ADDRESS.DAI,
        ADDRESS.FRAX,
        ADDRESS.FRXETH,
        ADDRESS.ETH,
        ADDRESS.WBTC,
        ADDRESS.BAL
      ],
      [
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address,
        chainlinkAdapterOracle.address
      ]
    )
  })

  beforeEach(async () => {
    const BalancerPairOracleFactory = await ethers.getContractFactory(CONTRACT_NAMES.BalancerPairOracle);
    oracle = <BalancerPairOracle>await BalancerPairOracleFactory.deploy(
      chainlinkAdapterOracle.address
    );
    await oracle.deployed();
  })

  describe("Price Feed", () => {
    it("Balancer USDC-DAI-USDT Stable Lp Price", async () => {
      let price0 = await oracle.callStatic.getPrice(ADDRESS.BAL_WBTC_WETH);
      let price1 = await oracle.callStatic.getPrice(ADDRESS.BAL_BAL_WETH);
      console.log("Balancer WBTC-WETH LP Price:", utils.formatUnits(price0, 18));
      console.log("Balancer BAL-WETH LP Price:", utils.formatUnits(price1, 18));
    })
  })
});