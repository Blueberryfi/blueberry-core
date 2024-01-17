import { expect } from 'chai';
import { BigNumber } from 'ethers';
import { ethers, upgrades } from 'hardhat';
import { ADDRESS } from '../../constant';
import { WERC20 } from '../../typechain-types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

const USDC = ADDRESS.USDC;

describe('Wrapped ERC20', () => {
  let werc20: WERC20;
  let admin: SignerWithAddress;
  before(async () => {
    [admin] = await ethers.getSigners();
    const WERC20 = await ethers.getContractFactory('WERC20');
    werc20 = <WERC20>await upgrades.deployProxy(WERC20, [admin.address], { unsafeAllow: ['delegatecall'] });
  });

  describe('Constructor', () => {
    it('should revert initializing twice', async () => {
      await expect(werc20.initialize(admin.address)).to.be.revertedWith(
        'Initializable: contract is already initialized'
      );
    });
  });

  it('should return underlying token address from tokenId', async () => {
    const tokenId = BigNumber.from(USDC);
    expect(await werc20.getUnderlyingToken(tokenId)).to.be.equal(USDC);

    await expect(werc20.getUnderlyingToken(ethers.constants.MaxUint256))
      .to.be.revertedWithCustomError(werc20, 'INVALID_TOKEN_ID')
      .withArgs(ethers.constants.MaxUint256);
  });
});
