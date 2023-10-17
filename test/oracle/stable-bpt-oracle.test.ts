import chai, { expect } from "chai";
import { BigNumber, utils } from "ethers";
import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ADDRESS, CONTRACT_NAMES } from "../../constant";
import {
  ChainlinkAdapterOracle,
  MockOracle,
  WERC20,
  StableBPTOracle,
  CoreOracle,
} from "../../typechain-types";

import { near } from "../assertions/near";
import { roughlyNear } from "../assertions/roughlyNear";

chai.use(near);
chai.use(roughlyNear);

describe("Core Oracle", () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;

  let coreOracle: CoreOracle;
  let stableBPTOracle: StableBPTOracle;
  let werc20: WERC20;

  before(async () => {
    [admin, alice] = await ethers.getSigners();

    const CoreOracle = await ethers.getContractFactory(
      CONTRACT_NAMES.CoreOracle
    );
    coreOracle = <CoreOracle>(
      await upgrades.deployProxy(CoreOracle, { unsafeAllow: ["delegatecall"] })
    );
    await coreOracle.deployed();
  });

  beforeEach(async () => {
    const StableBPTOracleFactory = await ethers.getContractFactory(
      CONTRACT_NAMES.StableBPTOracle
    );
    stableBPTOracle = <StableBPTOracle>(
      await StableBPTOracleFactory.deploy(coreOracle.address)
    );
  });

  // TODO: fix the errors here noobie
  //   describe("Get Price", () => {
  //     it("should return the correct price for a token", async () => {
  //       const ethPriceInUSD = await stableBPTOracle.callStatic.getPrice(
  //         ADDRESS.WETH
  //       );
  //       console.log(ethPriceInUSD);
  //     });
  //   });
});
