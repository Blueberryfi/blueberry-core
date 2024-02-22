import chai, { assert, expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ADDRESS, CONTRACT_NAMES } from '../../constant';
import { CoreOracle, ChainlinkAdapterOracle, ERC4626Oracle } from '../../typechain-types';

import { near } from '../assertions/near';
import { roughlyNear } from '../assertions/roughlyNear';
import { fork } from '../helpers';

chai.use(near);
chai.use(roughlyNear);

/* eslint-disable @typescript-eslint/no-unused-vars */
describe('ERC4626 Oracle', () => {
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;

  let erc4626Oracle: ERC4626Oracle;
  let coreOracle: CoreOracle;
  let chainlinkOracle: ChainlinkAdapterOracle;

  before(async () => {
    [admin, alice] = await ethers.getSigners();
    await fork(1, 19272826);

    const CoreOracle = await ethers.getContractFactory(CONTRACT_NAMES.CoreOracle);
    coreOracle = <CoreOracle>await upgrades.deployProxy(CoreOracle, [admin.address], { unsafeAllow: ['delegatecall'] });

    const ChainlinkAdapterOracle = await ethers.getContractFactory(CONTRACT_NAMES.ChainlinkAdapterOracle);
    chainlinkOracle = <ChainlinkAdapterOracle>await upgrades.deployProxy(ChainlinkAdapterOracle, [admin.address], {
      unsafeAllow: ['delegatecall'],
    });
    await chainlinkOracle.deployed();

    const ERC4626Oracle = await ethers.getContractFactory(CONTRACT_NAMES.ERC4626Oracle);
    erc4626Oracle = <ERC4626Oracle>await upgrades.deployProxy(ERC4626Oracle, [coreOracle.address, admin.address], {
      unsafeAllow: ['delegatecall'],
    });
    await erc4626Oracle.deployed();
  });

  describe('Owner', () => {
    it('should be able to register tokens', async () => {
      await expect(erc4626Oracle.connect(alice).registerToken(ADDRESS.apxETH)).to.be.revertedWith(
        'Ownable: caller is not the owner'
      );

      await erc4626Oracle.registerToken(ADDRESS.apxETH);
    });
  });

  describe('Token Pricing', () => {
    it('should return correct price of apxETH', async () => {
      const threeThousand = ethers.utils.parseEther('3000');
      const thirtyTwoHundred = ethers.utils.parseEther('3300');

      await chainlinkOracle.setPriceFeeds([ADDRESS.pxETH], ['0x19219BC90F48DeE4d5cF202E09c438FAacFd8Bea']);
      await chainlinkOracle.setPriceFeeds([ADDRESS.CHAINLINK_ETH], ['0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419']);
      await chainlinkOracle.setTimeGap([ADDRESS.pxETH], [40000]);
      await chainlinkOracle.setTimeGap([ADDRESS.CHAINLINK_ETH], [40000]);
      await chainlinkOracle.setEthDenominatedToken(ADDRESS.pxETH, true);

      await coreOracle.setRoutes([ADDRESS.pxETH], [chainlinkOracle.address]);

      await erc4626Oracle.registerToken(ADDRESS.apxETH);
      const price = await erc4626Oracle.getPrice(ADDRESS.apxETH);

      assert(price > threeThousand, 'Price is greater than 3000');
      assert(price < thirtyTwoHundred, 'Price is less than 3200');
    });

    it('should return correct price of sDAI', async () => {
      const pointNine = ethers.utils.parseEther('0.9');
      const onePointOne = ethers.utils.parseEther('1.1');

      await chainlinkOracle.setPriceFeeds([ADDRESS.DAI], ['0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9']);
      await chainlinkOracle.setTimeGap([ADDRESS.DAI], [40000]);

      await coreOracle.setRoutes([ADDRESS.DAI], [chainlinkOracle.address]);

      const sDAI = '0x83F20F44975D03b1b09e64809B757c47f942BEeA';
      await erc4626Oracle.registerToken(sDAI);
      const price = await erc4626Oracle.getPrice(sDAI);

      assert(price.gt(pointNine), 'Price is greater than 0.9');
      assert(price.lt(onePointOne), 'Price is less than 1.1');
    });
  });
});
