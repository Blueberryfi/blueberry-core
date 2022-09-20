import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { CONTRACT_NAMES } from "../../constants"
import { CoreOracle, MockERC20, MockWETH, SimpleOracle } from '../../typechain-types';
import { setupBasic } from '../helpers/setup-basic';

describe('Core Oracle', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let eve: SignerWithAddress;
  let coreOracle: CoreOracle;

  before(async () => {
    [admin, alice, bob, eve] = await ethers.getSigners();
  })
  describe("Route", () => {
    let weth: MockWETH;
    let usdc: MockERC20;
    let usdt: MockERC20;
    let dai: MockERC20;
    let simpleOracle: SimpleOracle;
    beforeEach(async () => {
      const fixture = await setupBasic();
      weth = fixture.mockWETH;
      usdt = fixture.usdt;
      usdc = fixture.usdc;
      dai = fixture.dai;
      simpleOracle = fixture.simpleOracle;
    })
    it("should be able to set route", async () => {
      expect(await coreOracle.routes(dai.address)).to.be.equal(ethers.constants.AddressZero);
      expect(await coreOracle.routes(usdt.address)).to.be.equal(ethers.constants.AddressZero);
      expect(await coreOracle.routes(usdc.address)).to.be.equal(ethers.constants.AddressZero);

      await simpleOracle.setPrice([dai.address, usdc.address, usdt.address], [1, 2, 3]);

      // test multiple sources
      const SimpleOracle = await ethers.getContractFactory(CONTRACT_NAMES.SimpleOracle);
      const simpleOracle1 = <SimpleOracle>await SimpleOracle.deploy();
      await simpleOracle1.deployed();
      await simpleOracle1.setPrice([dai.address, usdc.address, usdt.address], [4, 5, 6]);

      await coreOracle.setRoute(
        [dai.address, usdc.address, usdt.address],
        [simpleOracle.address, simpleOracle1.address, simpleOracle.address]
      );

      expect(await coreOracle.getPrice(dai.address)).to.be.equal(1);
      expect(await coreOracle.getPrice(usdc.address)).to.be.equal(5);
      expect(await coreOracle.getPrice(usdt.address)).to.be.equal(3);

      await expect(coreOracle.getPrice(weth.address)).to.be.reverted;

      // reset prices
      await simpleOracle.setPrice([dai.address, usdc.address, usdt.address], [7, 8, 9]);
      await simpleOracle1.setPrice([dai.address, usdc.address, usdt.address], [10, 11, 12]);

      expect(await coreOracle.getPrice(dai.address)).to.be.equal(7);
      expect(await coreOracle.getPrice(usdc.address)).to.be.equal(11);
      expect(await coreOracle.getPrice(usdt.address)).to.be.equal(9);

      // re-route
      coreOracle.setRoute(
        [dai.address, usdc.address, usdt.address],
        [simpleOracle1.address, ethers.constants.AddressZero, simpleOracle1.address]
      )

      expect(await coreOracle.getPrice(dai.address)).to.be.equal(10);
      expect(await coreOracle.getPrice(usdt.address)).to.be.equal(12);

      await expect(coreOracle.getPrice(usdc.address)).to.be.reverted;
    })
    it("should require same length", async () => {
      coreOracle.setRoute([], []);

      await expect(
        coreOracle.setRoute([dai.address], [])
      ).to.be.revertedWith('inconsistent length');

      await expect(
        coreOracle.setRoute([], [ethers.constants.AddressZero, ethers.constants.AddressZero])
      ).to.be.revertedWith('inconsistent length');

      await expect(
        coreOracle.setRoute(
          [dai.address, usdt.address],
          [ethers.constants.AddressZero]
        )
      ).to.be.revertedWith('inconsistent length');
    })
  })
})