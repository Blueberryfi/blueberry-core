import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber, utils } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { MockOracle, UniswapV3AdapterOracle } from '../../typechain-types';

/* eslint-disable @typescript-eslint/no-unused-vars */
describe('Uniswap V3 Oracle', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;

  let mockOracle: MockOracle;
  let uniswapV3Oracle: UniswapV3AdapterOracle;

  before(async () => {
    [admin, alice] = await ethers.getSigners();

    const LinkedLibFactory = await ethers.getContractFactory('UniV3WrappedLib');
    const LibInstance = await LinkedLibFactory.deploy();
    console.log('Uni V3 Lib Wrapper:', LibInstance.address);
    const MockOracle = await ethers.getContractFactory(CONTRACT_NAMES.MockOracle);
    mockOracle = <MockOracle>await MockOracle.deploy();
    await mockOracle.deployed();

    const UniswapV3AdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.UniswapV3AdapterOracle, {
      libraries: {
        UniV3WrappedLibContainer: LibInstance.address,
      },
    });
    uniswapV3Oracle = <UniswapV3AdapterOracle>await upgrades.deployProxy(
      UniswapV3AdapterOracle,
      [mockOracle.address, admin.address],
      {
        unsafeAllow: ['delegatecall', 'external-library-linking'],
      }
    );
    await uniswapV3Oracle.deployed();
  });

  describe('Owner', () => {
    it('should be able to set stable pools', async () => {
      await expect(
        uniswapV3Oracle
          .connect(alice)
          .setStablePools([ADDRESS.UNI, ADDRESS.ICHI], [ADDRESS.UNI_V3_UNI_USDC, ADDRESS.UNI_V3_ICHI_USDC])
      ).to.be.revertedWith('Ownable: caller is not the owner');

      await expect(
        uniswapV3Oracle.setStablePools([ADDRESS.UNI], [ADDRESS.UNI_V3_UNI_USDC, ADDRESS.UNI_V3_ICHI_USDC])
      ).to.be.revertedWithCustomError(uniswapV3Oracle, 'INPUT_ARRAY_MISMATCH');

      await expect(
        uniswapV3Oracle.setStablePools(
          [ADDRESS.UNI, ethers.constants.AddressZero],
          [ADDRESS.UNI_V3_UNI_USDC, ADDRESS.UNI_V3_ICHI_USDC]
        )
      ).to.be.revertedWithCustomError(uniswapV3Oracle, 'ZERO_ADDRESS');

      await expect(
        uniswapV3Oracle.setStablePools(
          [ADDRESS.UNI, ADDRESS.ICHI],
          [ADDRESS.UNI_V3_UNI_USDC, ethers.constants.AddressZero]
        )
      ).to.be.revertedWithCustomError(uniswapV3Oracle, 'ZERO_ADDRESS');

      await expect(uniswapV3Oracle.setStablePools([ADDRESS.CRV], [ADDRESS.UNI_V3_UNI_USDC]))
        .to.be.revertedWithCustomError(uniswapV3Oracle, 'NO_STABLEPOOL')
        .withArgs(ADDRESS.UNI_V3_UNI_USDC);

      await expect(
        uniswapV3Oracle.setStablePools([ADDRESS.UNI, ADDRESS.ICHI], [ADDRESS.UNI_V3_UNI_USDC, ADDRESS.UNI_V3_ICHI_USDC])
      ).to.be.emit(uniswapV3Oracle, 'SetPoolStable');

      const stablePool = await uniswapV3Oracle.getStablePool(ADDRESS.UNI);
      expect(stablePool).to.be.equal(ADDRESS.UNI_V3_UNI_USDC);
    });
    it('should be able to set times ago', async () => {
      await expect(
        uniswapV3Oracle.connect(alice).setTimeGap([ADDRESS.UNI, ADDRESS.ICHI], [3600, 3600])
      ).to.be.revertedWith('Ownable: caller is not the owner');

      await expect(
        uniswapV3Oracle.setTimeGap([ADDRESS.UNI, ADDRESS.ICHI], [3600, 3600, 3600])
      ).to.be.revertedWithCustomError(uniswapV3Oracle, 'INPUT_ARRAY_MISMATCH');

      await expect(
        uniswapV3Oracle.setTimeGap([ADDRESS.UNI, ethers.constants.AddressZero], [3600, 3600])
      ).to.be.revertedWithCustomError(uniswapV3Oracle, 'ZERO_ADDRESS');

      await expect(uniswapV3Oracle.setTimeGap([ADDRESS.UNI, ADDRESS.ICHI], [3600, 5]))
        .to.be.revertedWithCustomError(uniswapV3Oracle, 'TOO_LOW_MEAN')
        .withArgs(5);

      await expect(uniswapV3Oracle.setTimeGap([ADDRESS.UNI, ADDRESS.ICHI], [3600, 3600])).to.be.emit(
        uniswapV3Oracle,
        'SetTimeGap'
      );

      expect(await uniswapV3Oracle.getTimeGap(ADDRESS.UNI)).to.be.equal(3600);
    });
  });

  describe('Price Feeds', () => {
    beforeEach(async () => {
      await mockOracle.setPrice(
        [ADDRESS.USDC],
        [BigNumber.from(10).pow(18)] // $1
      );
      await uniswapV3Oracle.setStablePools(
        [ADDRESS.UNI, ADDRESS.ICHI, ADDRESS.CRV, ADDRESS.DAI],
        [ADDRESS.UNI_V3_UNI_USDC, ADDRESS.UNI_V3_ICHI_USDC, ADDRESS.UNI_V3_USDC_CRV, ADDRESS.UNI_V3_USDC_DAI]
      );

      await uniswapV3Oracle.connect(admin).registerToken(ADDRESS.UNI);
      await uniswapV3Oracle.connect(admin).registerToken(ADDRESS.ICHI);
      await uniswapV3Oracle.connect(admin).registerToken(ADDRESS.CRV);
      await uniswapV3Oracle.connect(admin).registerToken(ADDRESS.DAI);

      await uniswapV3Oracle.setTimeGap(
        [ADDRESS.UNI, ADDRESS.ICHI, ADDRESS.CRV],
        [3600, 3600, 3600] // timeAgo - 1 hour
      );
    });

    it('should revert when mean time is not set', async () => {
      await expect(uniswapV3Oracle.callStatic.getPrice(ADDRESS.DAI))
        .to.be.revertedWithCustomError(uniswapV3Oracle, 'NO_MEAN')
        .withArgs(ADDRESS.DAI);
    });
    it('should revert when stable pool is not set', async () => {
      await uniswapV3Oracle.setTimeGap([ADDRESS.USDC], [3600]);
      await expect(uniswapV3Oracle.callStatic.getPrice(ADDRESS.USDC))
        .to.be.revertedWithCustomError(uniswapV3Oracle, 'ORACLE_NOT_SUPPORT_LP')
        .withArgs(ADDRESS.USDC);
    });
    it('$UNI Price', async () => {
      const price = await uniswapV3Oracle.callStatic.getPrice(ADDRESS.UNI);
      console.log(utils.formatUnits(price, 18));
    });
    it('$ICHI Price', async () => {
      const price = await uniswapV3Oracle.callStatic.getPrice(ADDRESS.ICHI);
      console.log(utils.formatUnits(price, 18));
    });
  });
});
