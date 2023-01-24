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
        coreOracle.connect(alice).setRoute(
          [ADDRESS.USDC],
          [mockOracle.address]
        )
      ).to.be.revertedWith('Ownable: caller is not the owner');

      await expect(
        coreOracle.setRoute(
          [ethers.constants.AddressZero],
          [mockOracle.address]
        )
      ).to.be.revertedWith('ZERO_ADDRESS');

      await expect(
        coreOracle.setRoute(
          [ADDRESS.USDC],
          [ethers.constants.AddressZero],
        )
      ).to.be.revertedWith('ZERO_ADDRESS');

      await expect(
        coreOracle.setRoute(
          [ADDRESS.USDC, ADDRESS.USDT],
          [mockOracle.address]
        )
      ).to.be.revertedWith('INPUT_ARRAY_MISMATCH');

      await expect(
        coreOracle.setRoute([ADDRESS.USDC], [mockOracle.address])
      ).to.be.emit(coreOracle, "SetRoute");

      const tokenSetting = await coreOracle.tokenSettings(ADDRESS.USDC);
      expect(tokenSetting.route).to.be.equal(mockOracle.address);
    })
    it("should be able to set token settings", async () => {
      await expect(coreOracle.connect(alice).setTokenSettings(
        [ADDRESS.USDC],
        [{
          liqThreshold: 9000,
          route: mockOracle.address
        }]
      )).to.be.revertedWith('Ownable: caller is not the owner');

      await expect(coreOracle.setTokenSettings(
        [ADDRESS.USDC],
        [{
          liqThreshold: 10050,
          route: mockOracle.address
        }]
      )).to.be.revertedWith('LIQ_THRESHOLD_TOO_HIGH(10050)');

      await expect(coreOracle.setTokenSettings(
        [ADDRESS.USDC],
        [{
          liqThreshold: 9000,
          route: ethers.constants.AddressZero
        }]
      )).to.be.revertedWith('ZERO_ADDRESS');

      await expect(coreOracle.setTokenSettings(
        [ethers.constants.AddressZero],
        [{
          liqThreshold: 9000,
          route: mockOracle.address
        }]
      )).to.be.revertedWith('ZERO_ADDRESS');

      await expect(coreOracle.setTokenSettings(
        [ADDRESS.USDC, ADDRESS.USDT],
        [{
          liqThreshold: 9000,
          route: mockOracle.address
        }]
      )).to.be.revertedWith('INPUT_ARRAY_MISMATCH');

      await expect(
        coreOracle.setTokenSettings(
          [ADDRESS.USDC],
          [{
            liqThreshold: 9000,
            route: mockOracle.address
          }]
        )
      ).to.be.emit(coreOracle, "SetTokenSetting");

      const tokenSetting = await coreOracle.tokenSettings(ADDRESS.USDC);
      expect(tokenSetting.route).to.be.equal(mockOracle.address);
      expect(tokenSetting.liqThreshold).to.be.equal(9000);
    })
    it("should be able to unset token settings", async () => {
      await coreOracle.setTokenSettings(
        [ADDRESS.USDC],
        [{
          liqThreshold: 9000,
          route: mockOracle.address
        }]
      );

      await expect(
        coreOracle.connect(alice).removeTokenSettings([ADDRESS.USDC])
      ).to.be.revertedWith('Ownable: caller is not the owner');

      await expect(
        coreOracle.removeTokenSettings([ADDRESS.USDC])
      ).to.be.emit(coreOracle, 'RemoveTokenSetting');

      const tokenSetting = await coreOracle.tokenSettings(ADDRESS.USDC);
      expect(tokenSetting.route).to.be.equal(ethers.constants.AddressZero);
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
      await coreOracle.setRoute([ADDRESS.USDC], [mockOracle.address]);
    })

    it("should to able to get if the wrapper is supported or not", async () => {
      await coreOracle.setWhitelistERC1155([werc20.address], true);

      expect(
        await coreOracle.supportWrappedToken(ADDRESS.USDC, 0)
      ).to.be.false;

      let collId = BigNumber.from(ADDRESS.USDC);
      expect(
        await coreOracle.supportWrappedToken(werc20.address, collId)
      ).to.be.true;

      collId = BigNumber.from(ADDRESS.USDT);
      expect(await coreOracle.supportWrappedToken(werc20.address, collId)).to.be.false;
    })
    it("should be able to get if the token price is supported or not", async () => {
      await coreOracle.setRoute([ADDRESS.USDT], [mockOracle.address]);
      await mockOracle.setPrice([ADDRESS.USDC], [utils.parseEther("1")]);

      expect(await coreOracle.support(ADDRESS.USDC)).to.be.true;

      await expect(
        coreOracle.getPrice(ADDRESS.USDT)
      ).to.be.revertedWith("PRICE_FAILED");
    })
  })
  // TODO: Cover getCollateralValue, getDebtValue, getUnderlyingValue, getLiqThreshold
});
