import chai, { expect } from 'chai';
import { BigNumber, utils } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import {
  BandAdapterOracle,
  CoreOracle,
  IStdReference,
  MockOracle,
  WERC20,
} from '../../typechain-types';
import BandOracleABI from '../../abi/IStdReference.json';

import { solidity } from 'ethereum-waffle'
import { near } from '../assertions/near'
import { roughlyNear } from '../assertions/roughlyNear'

chai.use(solidity)
chai.use(near)
chai.use(roughlyNear)

const OneDay = 86400;

describe('Core Oracle', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;

  let mockOracle: MockOracle;
  let coreOracle: CoreOracle;
  let werc20: WERC20;

  before(async () => {
    [admin, alice] = await ethers.getSigners();
  });

  beforeEach(async () => {
    const MockOracle = await ethers.getContractFactory(CONTRACT_NAMES.MockOracle);
    mockOracle = <MockOracle>await MockOracle.deploy();

    const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
    coreOracle = <CoreOracle>await upgrades.deployProxy(CoreOracle);

    const WERC20 = await ethers.getContractFactory(CONTRACT_NAMES.WERC20);
    werc20 = <WERC20>await WERC20.deploy();
    await werc20.deployed();
  })

  describe("Owner", () => {
    it("should be able to set routes", async () => {
      await expect(
        coreOracle.connect(alice).setRoutes(
          [ADDRESS.USDC],
          [mockOracle.address]
        )
      ).to.be.revertedWith('Ownable: caller is not the owner');

      await expect(
        coreOracle.setRoutes(
          [ethers.constants.AddressZero],
          [mockOracle.address]
        )
      ).to.be.revertedWith('ZERO_ADDRESS');

      await expect(
        coreOracle.setRoutes(
          [ADDRESS.USDC],
          [ethers.constants.AddressZero],
        )
      ).to.be.revertedWith('ZERO_ADDRESS');

      await expect(
        coreOracle.setRoutes(
          [ADDRESS.USDC, ADDRESS.USDT],
          [mockOracle.address]
        )
      ).to.be.revertedWith('INPUT_ARRAY_MISMATCH');

      await expect(
        coreOracle.setRoutes([ADDRESS.USDC], [mockOracle.address])
      ).to.be.emit(coreOracle, "SetRoute");

      const route = await coreOracle.routes(ADDRESS.USDC);
      expect(route).to.be.equal(mockOracle.address);
    })
    it("should be able to set liquidation thresholds", async () => {
      await expect(coreOracle.connect(alice).setLiqThresholds(
        [ADDRESS.USDC],
        [9000]
      )).to.be.revertedWith('Ownable: caller is not the owner');

      await expect(coreOracle.setLiqThresholds(
        [ADDRESS.USDC],
        [10050]
      )).to.be.revertedWith('LIQ_THRESHOLD_TOO_HIGH(10050)');

      await expect(coreOracle.setLiqThresholds(
        [ADDRESS.USDC],
        [7500]
      )).to.be.revertedWith('LIQ_THRESHOLD_TOO_LOW(7500)');

      await expect(coreOracle.setLiqThresholds(
        [ethers.constants.AddressZero],
        [9000]
      )).to.be.revertedWith('ZERO_ADDRESS');

      await expect(coreOracle.setLiqThresholds(
        [ADDRESS.USDC, ADDRESS.USDT],
        [9000]
      )).to.be.revertedWith('INPUT_ARRAY_MISMATCH');

      await expect(
        coreOracle.setLiqThresholds(
          [ADDRESS.USDC],
          [9000]
        )
      ).to.be.emit(coreOracle, "SetLiqThreshold");

      const liqThreshold = await coreOracle.liqThresholds(ADDRESS.USDC);
      expect(liqThreshold).to.be.equal(9000);
    })
    it("should be able to whtielist erc1155 - wrapped tokens", async () => {
      await expect(
        coreOracle.connect(alice).setWhitelistERC1155([ADDRESS.USDC], true)
      ).to.be.revertedWith('Ownable: caller is not the owner');

      await expect(
        coreOracle.setWhitelistERC1155([ethers.constants.AddressZero], true)
      ).to.be.revertedWith('ZERO_ADDRESS');

      await expect(
        coreOracle.setWhitelistERC1155([ADDRESS.USDC], true)
      ).to.be.emit(coreOracle, "SetWhitelist");

      const whitelist = await coreOracle.whitelistedERC1155(ADDRESS.USDC);
      expect(whitelist).to.be.equal(true);
    })
  })
  describe("Utils", () => {
    beforeEach(async () => {
      await coreOracle.setRoutes([ADDRESS.USDC], [mockOracle.address]);
    })

    it("should to able to get if the wrapper is supported or not", async () => {
      await coreOracle.setWhitelistERC1155([werc20.address], true);

      expect(
        await coreOracle.isWrappedTokenSupported(ADDRESS.USDC, 0)
      ).to.be.false;

      let collId = BigNumber.from(ADDRESS.USDC);
      expect(
        await coreOracle.isWrappedTokenSupported(werc20.address, collId)
      ).to.be.true;

      collId = BigNumber.from(ADDRESS.USDT);
      expect(await coreOracle.isWrappedTokenSupported(werc20.address, collId)).to.be.false;
    })
    it("should be able to get if the token price is supported or not", async () => {
      await coreOracle.setRoutes([ADDRESS.USDT], [mockOracle.address]);
      await mockOracle.setPrice([ADDRESS.USDC], [utils.parseEther("1")]);

      expect(await coreOracle.isTokenSupported(ADDRESS.USDC)).to.be.true;

      await expect(
        coreOracle.getPrice(ADDRESS.USDT)
      ).to.be.revertedWith("PRICE_FAILED");
    })
  })
  describe("Value", () => {
    // TODO: Cover getPositionValue, getTokenValue
    describe("Debt Value", async () => {
      it("should revert when oracle route is not set", async () => {
        await expect(
          coreOracle.getTokenValue(ADDRESS.CRV, 100)
        ).to.be.revertedWith("NO_ORACLE_ROUTE");
      })
    })
  })
});
