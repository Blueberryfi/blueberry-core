import chai, { expect } from "chai";
import { BigNumber, utils } from "ethers";
import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ADDRESS, CONTRACT_NAMES } from "../../constant";
import {
  ChainlinkAdapterOracle,
  CoreOracle,
  CurveStableOracle,
  CurveVolatileOracle,
  CurveTricryptoOracle,
} from "../../typechain-types";
import { roughlyNear } from "../assertions/roughlyNear";

chai.use(roughlyNear);

const OneDay = 86400;

describe("Curve LP Oracle", () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;

  let stableOracle: CurveStableOracle;
  let volatileOracle: CurveVolatileOracle;
  let tricryptoOracle: CurveTricryptoOracle;
  let coreOracle: CoreOracle;
  let chainlinkAdapterOracle: ChainlinkAdapterOracle;

  before(async () => {
    [admin, alice] = await ethers.getSigners();

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
        ADDRESS.SUSD,
        ADDRESS.FRAX,
        ADDRESS.FRXETH,
        ADDRESS.CHAINLINK_ETH,
        ADDRESS.CHAINLINK_BTC,
        ADDRESS.CVX,
        ADDRESS.CRV,
      ],
      [
        OneDay,
        OneDay,
        OneDay,
        OneDay,
        OneDay,
        OneDay,
        OneDay,
        OneDay,
        OneDay,
        OneDay,
      ]
    );

    const CoreOracle = await ethers.getContractFactory(
      CONTRACT_NAMES.CoreOracle
    );
    coreOracle = <CoreOracle>await upgrades.deployProxy(CoreOracle);
    await coreOracle.deployed();
  });

  beforeEach(async () => {
    const CurveStableOracleFactory = await ethers.getContractFactory(
      CONTRACT_NAMES.CurveStableOracle
    );
    stableOracle = <CurveStableOracle>(
      await CurveStableOracleFactory.deploy(
        coreOracle.address,
        ADDRESS.CRV_ADDRESS_PROVIDER
      )
    );
    await stableOracle.deployed();
    const CurveVolatileOracleFactory = await ethers.getContractFactory(
      CONTRACT_NAMES.CurveVolatileOracle
    );
    volatileOracle = <CurveVolatileOracle>(
      await CurveVolatileOracleFactory.deploy(
        coreOracle.address,
        ADDRESS.CRV_ADDRESS_PROVIDER
      )
    );
    await volatileOracle.deployed();
    const CurveTricryptoOracleFactory = await ethers.getContractFactory(
      CONTRACT_NAMES.CurveTricryptoOracle
    );
    tricryptoOracle = <CurveTricryptoOracle>(
      await CurveTricryptoOracleFactory.deploy(
        coreOracle.address,
        ADDRESS.CRV_ADDRESS_PROVIDER
      )
    );
    await tricryptoOracle.deployed();
  });

  describe("Owner", () => {
    it("should be able to set limiter", async () => {
      let poolInfo = await volatileOracle.callStatic.getPoolInfo(
        ADDRESS.CRV_CVXETH
      );

      await expect(
        volatileOracle
          .connect(alice)
          .setLimiter(ADDRESS.CRV_CVXETH, poolInfo.virtualPrice)
      ).to.be.revertedWith("Ownable: caller is not the owner");

      await expect(
        volatileOracle.setLimiter(ADDRESS.CRV_CVXETH, 0)
      ).to.be.revertedWithCustomError(volatileOracle, "INCORRECT_LIMITS");

      await expect(
        volatileOracle.setLimiter(
          ADDRESS.CRV_CVXETH,
          poolInfo.virtualPrice.add(1)
        )
      ).to.be.revertedWithCustomError(volatileOracle, "INCORRECT_LIMITS");

      await expect(
        volatileOracle.setLimiter(
          ADDRESS.CRV_CVXETH,
          poolInfo.virtualPrice.mul(9).div(10)
        )
      ).to.be.revertedWithCustomError(volatileOracle, "INCORRECT_LIMITS");
    });
  });

  describe("Price Feed", () => {
    it("Getting PoolInfo", async () => {
      console.log(
        "3CrvPool",
        await stableOracle.callStatic.getPoolInfo(ADDRESS.CRV_3Crv)
      );
      console.log(
        "TriCrypto2 Pool",
        await tricryptoOracle.callStatic.getPoolInfo(ADDRESS.CRV_TriCrypto)
      );
      console.log(
        "FRAX/USDC USD Pool",
        await stableOracle.callStatic.getPoolInfo(ADDRESS.CRV_FRAXUSDC)
      );
      console.log(
        "frxETH/ETH ETH Pool",
        await stableOracle.callStatic.getPoolInfo(ADDRESS.CRV_FRXETH)
      );
      console.log(
        "CRV/ETH Crypto Pool",
        await volatileOracle.callStatic.getPoolInfo(ADDRESS.CRV_CRVETH)
      );
      console.log(
        "CVX/ETH Crypto Pool",
        await volatileOracle.callStatic.getPoolInfo(ADDRESS.CRV_CVXETH)
      );
      console.log(
        "cvxCRV/CRV Factory Pool",
        await stableOracle.callStatic.getPoolInfo(ADDRESS.CRV_CVXCRV_CRV)
      );
      console.log(
        "ALCX/FRAXBP Crypto Factory Pool",
        await volatileOracle.callStatic.getPoolInfo(ADDRESS.CRV_ALCX_FRAXBP)
      );
    });

    it("Should fail to get price when base oracle is not set", async () => {
      await expect(stableOracle.callStatic.getPrice(ADDRESS.CRV_3Crv)).to.be
        .reverted;

      await expect(tricryptoOracle.callStatic.getPrice(ADDRESS.CRV_CVXETH))
        .to.be.revertedWithCustomError(tricryptoOracle, "ORACLE_NOT_SUPPORT_LP")
        .withArgs(ADDRESS.CRV_CVXETH);
    });

    it("Crv Lp Price", async () => {
      await chainlinkAdapterOracle.setTokenRemappings(
        [ADDRESS.WETH, ADDRESS.FRXETH, ADDRESS.WBTC],
        [ADDRESS.CHAINLINK_ETH, ADDRESS.CHAINLINK_ETH, ADDRESS.CHAINLINK_BTC]
      );

      await coreOracle.setRoutes(
        [
          ADDRESS.USDC,
          ADDRESS.USDT,
          ADDRESS.DAI,
          ADDRESS.FRAX,
          ADDRESS.SUSD,
          ADDRESS.FRXETH,
          ADDRESS.ETH,
          ADDRESS.WETH,
          ADDRESS.WBTC,
          ADDRESS.CVX,
          ADDRESS.CRV,
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
          chainlinkAdapterOracle.address,
        ]
      );

      let poolInfo = await volatileOracle.callStatic.getPoolInfo(
        ADDRESS.CRV_CVXETH
      );
      await volatileOracle.setLimiter(
        ADDRESS.CRV_CVXETH,
        poolInfo.virtualPrice
      );

      poolInfo = await volatileOracle.callStatic.getPoolInfo(
        ADDRESS.CRV_CRVETH
      );
      await volatileOracle.setLimiter(
        ADDRESS.CRV_CRVETH,
        poolInfo.virtualPrice
      );

      let price = await stableOracle.callStatic.getPrice(ADDRESS.CRV_3Crv);
      console.log("3CrvPool Price:", utils.formatUnits(price, 18));

      price = await tricryptoOracle.callStatic.getPrice(ADDRESS.CRV_TriCrypto);
      console.log("TriCrypto Price:", utils.formatUnits(price, 18));

      price = await stableOracle.callStatic.getPrice(ADDRESS.CRV_SUSD);
      console.log("DAI/USDC/USDT/sUSD Price:", utils.formatUnits(price, 18));

      price = await stableOracle.callStatic.getPrice(ADDRESS.CRV_FRAXUSDC);
      console.log("FRAX/USDC Price:", utils.formatUnits(price, 18));

      price = await volatileOracle.callStatic.getPrice(ADDRESS.CRV_CVXETH);
      console.log("CVX/ETH Price:", utils.formatUnits(price, 18));

      price = await volatileOracle.callStatic.getPrice(ADDRESS.CRV_CRVETH);
      console.log("CRV/ETH Price:", utils.formatUnits(price, 18));

      price = await stableOracle.callStatic.getPrice(ADDRESS.CRV_FRXETH);
      console.log("frxETH/ETH Price:", utils.formatUnits(price, 18));
    });
  });
});
